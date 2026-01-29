from rest_framework import viewsets, permissions, views, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.shortcuts import get_object_or_404
from django.utils import timezone
from .models import MockExam, MockExamInfo, MockExamQuestion
from core.models import StudentProfile
from .serializers import (
    MockExamSerializer, MockExamInfoSerializer, 
    MockExamConfirmSerializer, MockExamQuestionSerializer
)
from .omr import scan_omr, calculate_score
import io
from PIL import Image
import platform

# Helper from views.py
def get_poppler_path():
    system_name = platform.system()
    if system_name == 'Windows':
        return r"C:\Program Files (x86)\poppler\Library\bin"  
    else:
        return None

class MockExamInfoViewSet(viewsets.ModelViewSet):
    """
    모의고사 정답지(회차) 관리 API
    - 목록/생성/수정/삭제
    """
    queryset = MockExamInfo.objects.filter(is_active=True).order_by('-year', '-month')
    serializer_class = MockExamInfoSerializer
    permission_classes = [permissions.IsAuthenticated]
    
class MockExamQuestionViewSet(viewsets.ModelViewSet):
    """
    모의고사 개별 문항 수정 API
    """
    queryset = MockExamQuestion.objects.all().order_by('number')
    serializer_class = MockExamQuestionSerializer
    permission_classes = [permissions.IsAuthenticated]


    @action(detail=True, methods=['post'])
    def upload_answers(self, request, pk=None):
        """
        정답지 엑셀 업로드
        형식: 번호, 정답, 배점(선택), 유형(선택)
        """
        exam_info = self.get_object()
        file = request.FILES.get('file')
        if not file:
            return Response({'error': '파일이 제공되지 않았습니다.'}, status=400)
            
        try:
            import pandas as pd
            df = pd.read_excel(file, engine='openpyxl')
            
            # Clean headers (strip spaces)
            df.columns = df.columns.astype(str).str.strip()
            
            updated_count = 0
            
            # Map headers
            # Expected: '번호' or 'Number', '정답' or 'Answer', ...
            col_num = next((c for c in df.columns if '번호' in c or 'No' in c), None)
            col_ans = next((c for c in df.columns if '정답' in c or 'Answer' in c), None)
            col_score = next((c for c in df.columns if '배점' in c or 'Score' in c), None)
            
            if not col_num or not col_ans:
                return Response({'error': '엑셀에 [번호], [정답] 컬럼이 필수입니다.'}, status=400)
                
            questions = {q.number: q for q in exam_info.questions.all()}
            
            for _, row in df.iterrows():
                try:
                    num = int(row[col_num])
                    ans = int(row[col_ans])
                    
                    if num in questions:
                        q = questions[num]
                        q.correct_answer = ans
                        
                        # Score update optional
                        if col_score and pd.notnull(row[col_score]):
                            q.score = int(row[col_score])
                            
                        q.save()
                        updated_count += 1
                except Exception:
                    continue # Skip invalid rows
            
            return Response({'message': f'{updated_count}개 문항 정답 업데이트 완료'})
            
        except Exception as e:
            return Response({'error': str(e)}, status=500)

class MockExamViewSet(viewsets.ReadOnlyModelViewSet):
    """
    모의고사 성적 조회 API
    """
    serializer_class = MockExamSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, 'profile'):
            return MockExam.objects.filter(student=user.profile).order_by('-exam_date')
        return MockExam.objects.none()

class OMRScanView(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        exam_id = request.data.get('exam_info_id')
        uploaded_file = request.FILES.get('omr_file')
        
        if not exam_id or not uploaded_file:
            return Response({"error": "exam_info_id and omr_file required"}, status=400)

        exam_info = get_object_or_404(MockExamInfo, id=exam_id)
        results = []

        try:
            filename = uploaded_file.name.lower()
            images = []
            
            if filename.endswith('.pdf'):
                try:
                    from pdf2image import convert_from_bytes
                    images = convert_from_bytes(uploaded_file.read(), poppler_path=get_poppler_path())
                except ImportError:
                    return Response({"error": "pdf2image module missing"}, status=500)
            else:
                images = [Image.open(uploaded_file)]

            for i, pil_image in enumerate(images):
                img_byte_arr = io.BytesIO()
                pil_image.save(img_byte_arr, format='JPEG')
                img_bytes = img_byte_arr.getvalue()

                student_id_str, answers, debug_image = scan_omr(img_bytes)
                
                scan_status = "SUCCESS"
                error_msg = ""
                student_data = None
                score_data = None

                # 1. Identify Student
                if not student_id_str or len(student_id_str) < 4 or "?" in student_id_str:
                    scan_status = "FAIL" 
                    error_msg = f"수험번호 인식 실패 ({student_id_str})"
                    # Fail이어도 일단 넘기지만, Frontend에서 처리 필요
                else:

                    try:
                        # [Modified] 1. Try Attendance Code
                        student = StudentProfile.objects.filter(attendance_code=student_id_str).first()

                        # 2. Fallback: Try Username (Phone) EndsWith
                        if not student:
                            # If student_id_str is 8 digits (e.g. 12345678), matched against 01012345678
                            student = StudentProfile.objects.filter(user__username__endswith=student_id_str).first()
                        
                        # 3. Fallback: Try Phone Number EndsWith
                        if not student:
                             student = StudentProfile.objects.filter(phone_number__endswith=student_id_str).first()

                        if not student:
                            raise StudentProfile.DoesNotExist

                        student_data = {
                            "id": student.id,
                            "name": student.name,
                            "school": student.school.name if student.school else "",
                            "grade": student.current_grade_display
                        }
                    except StudentProfile.DoesNotExist:
                        scan_status = "FAIL"
                        error_msg = f"학생 정보 없음 ({student_id_str})"

                # 2. Calculate Score (if answers found)
                if scan_status == "SUCCESS" or (student_id_str and len(student_id_str) >= 4):
                     # 학생 식별 실패했더라도 OMR이 잘 읽혔으면 점수 계산은 해서 보여줄 수 있음 (수동 매핑용)
                     if not answers or len(answers) < 10:
                         scan_status = "FAIL"
                         error_msg = "답안 마킹 인식 실패"
                     else:
                         score_result = calculate_score(answers, exam_info)
                         score_data = score_result 
                
                results.append({
                    "page": i + 1,
                    "status": scan_status,
                    "error_msg": error_msg,
                    "student_id_raw": student_id_str,
                    "student": student_data,
                    "score_data": score_data,
                    "omr_image": debug_image
                })

            return Response({"results": results})
        except Exception as e:
            import traceback
            traceback.print_exc()
            return Response({"error": str(e)}, status=500)

class ScoreConfirmView(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        serializer = MockExamConfirmSerializer(data=request.data)
        if serializer.is_valid():
            exam_id = serializer.validated_data['exam_id']
            exam_info = get_object_or_404(MockExamInfo, id=exam_id)
            items = serializer.validated_data['results']
            
            created_count = 0
            for item in items:
                student = get_object_or_404(StudentProfile, id=item['student_id'])
                MockExam.objects.create(
                    student=student,
                    title=exam_info.title,
                    exam_date=timezone.now().date(),
                    score=item['score'],
                    grade=item['grade'],
                    wrong_listening=item['wrong_counts'].get('LISTENING', 0),
                    wrong_vocab=item['wrong_counts'].get('VOCAB', 0),
                    wrong_grammar=item['wrong_counts'].get('GRAMMAR', 0),
                    wrong_reading=item['wrong_counts'].get('READING', 0),
                    wrong_type_breakdown=item['wrong_type_breakdown'],
                    wrong_question_numbers=item['wrong_question_numbers'],
                    student_answers=item['student_answers'],
                    recorded_by=request.user
                )
                created_count += 1
            
            return Response({"message": f"Saved {created_count} results", "count": created_count})
        return Response(serializer.errors, status=400)
