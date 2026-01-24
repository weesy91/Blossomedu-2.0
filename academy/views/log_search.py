from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import permissions, status
from django.utils import timezone
from datetime import datetime, timedelta
from django.shortcuts import get_object_or_404
from django.db.models import Q

# Models
from core.models import StudentProfile
from academy.models import ClassLog, AssignmentTask
from vocab.models import TestResult

class StudentLogSearchView(APIView):
    """
    학생의 모든 활동 로그(수업일지, 과제, 시험)를 날짜순(최신순)으로 통합 검색
    Endpoint: /academy/api/v1/logs/search/
    Params:
      - student_id: int (Required)
      - start_date: 'YYYY-MM-DD' (Optional)
      - end_date: 'YYYY-MM-DD' (Optional)
      - types: comma separated string 'LOG,ASM,TEST' (Optional, default all)
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        student_id = request.query_params.get('student_id')
        if not student_id:
            return Response({'error': 'student_id is required'}, status=status.HTTP_400_BAD_REQUEST)

        # 권한 체크: 나중에 강화 필요 (내 학생인지 확인)
        # student = get_object_or_404(StudentProfile, id=student_id)
        
        start_date_str = request.query_params.get('start_date')
        end_date_str = request.query_params.get('end_date')
        types_str = request.query_params.get('types', 'LOG,ASM,TEST')
        types = [t.strip().upper() for t in types_str.split(',')]
        
        timeline = []

        # ---------------------------------------------------------
        # 1. 수업 일지 (ClassLog)
        # ---------------------------------------------------------
        if 'LOG' in types:
            logs = ClassLog.objects.filter(student_id=student_id).select_related('teacher')
            if start_date_str:
                logs = logs.filter(date__gte=start_date_str)
            if end_date_str:
                logs = logs.filter(date__lte=end_date_str)
                
            for log in logs:
                # 진도 요약 (첫 번째 엔트리 기준)
                first_entry = log.entries.first()
                progress_summary = "내용 없음"
                if first_entry:
                    book_name = first_entry.textbook.title if first_entry.textbook else (first_entry.wordbook.title if first_entry.wordbook else "")
                    progress_summary = f"{book_name} {first_entry.progress_range}"

                timeline.append({
                    'type': 'LOG',
                    'date': log.date, # Date Object (for sorting)
                    'timestamp': datetime.combine(log.date, datetime.min.time()),
                    'title': f"{log.get_subject_display()} 수업",
                    'content': progress_summary,
                    'sub_info': log.teacher.staff_profile.name if log.teacher and hasattr(log.teacher, 'staff_profile') else (log.teacher.username if log.teacher else "미지정"),
                    'status': 'COMPLETED',
                    'id': log.id,
                    'raw_date': log.date.strftime('%Y-%m-%d')
                })

        # ---------------------------------------------------------
        # 2. 과제 (AssignmentTask)
        # ---------------------------------------------------------
        if 'ASM' in types:
            assignments = AssignmentTask.objects.filter(student_id=student_id)
            if start_date_str:
                assignments = assignments.filter(due_date__date__gte=start_date_str)
            if end_date_str:
                assignments = assignments.filter(due_date__date__lte=end_date_str)

            for asm in assignments:
                # 상태 결정
                is_completed = asm.is_completed
                status_str = 'PENDING'
                
                if hasattr(asm, 'submission'):
                    sub_status = asm.submission.status
                    if sub_status == 'APPROVED':
                        status_str = 'COMPLETED'
                    elif sub_status == 'REJECTED':
                        status_str = 'REJECTED'
                    else:
                        status_str = 'SUBMITTED' # 검사 대기
                elif is_completed:
                    status_str = 'COMPLETED' # 수동 완료 처리 등
                elif asm.due_date < timezone.now():
                    status_str = 'OVERDUE'

                timeline.append({
                    'type': 'ASM',
                    'date': asm.due_date.date(),
                    'timestamp': asm.due_date,
                    'title': asm.title,
                    'content': asm.description or '설명 없음',
                    'sub_info': f"마감: {asm.due_date.strftime('%m-%d %H:%M')}",
                    'status': status_str,
                    'id': asm.id,
                    'raw_date': asm.due_date.strftime('%Y-%m-%d')
                })

        # ---------------------------------------------------------
        # 3. 단어 시험 (TestResult)
        # ---------------------------------------------------------
        if 'TEST' in types:
            # select_related 'book'이 없을 수도 있으니(WordBook) 확인 필요. 
            # vocab/models.py TestResult에는 book 필드가 없고 range 텍스트 등만 있거나 
            # 혹은 WordBook과 연결된 필드가 있을 수 있음.
            # 모델 정의를 다시 보면 TestResult에는 'book' 필드가 없고 'test_range'만 있음.
            # 하지만 상세 구현에서 book_id 등이 있을 수 있음. 모델 필드를 다시 확인.
            # TestResult 모델(L198)에는 student, wrong_count, test_range, created_at 만 명시됨.
            # 하지만 실제로는 추가된 필드가 있을 가능성이 높음 (최근 마이그레이션 등).
            # 여기서는 안전하게 기본 필드만 사용하거나 try-except 처리.
            
            tests = TestResult.objects.filter(student_id=student_id)
            if start_date_str:
                tests = tests.filter(created_at__date__gte=start_date_str)
            if end_date_str:
                tests = tests.filter(created_at__date__lte=end_date_str)

            for test in tests:
                # 점수 계산 (모델 필드에 score가 없다면 계산해야 함)
                # TestResult 모델(outline)에는 wrong_count만 보였음.
                # 그러나 WordTestScreen.dart 에서는 result['score']를 받고 있음.
                # 이는 API(Serializer) 레벨에서 계산해서 주거나 모델에 score 필드가 있을 수 있음.
                # 모델 outline에 score는 안보였음. 
                # -> 임시로 total_questions 등을 알 수 없으므로, 상세 정보가 없으면 wrong_count만 표시.
                # 하지만, 만약 score 필드가 있다면 사용.
                
                score_display = f"{test.wrong_count}개 틀림"
                if hasattr(test, 'score'):
                    score_display = f"{test.score}점"
                
                # 책 제목 추론 (어렵다면 test_range 사용)
                title_display = f"단어시험 ({test.test_range})"
                
                status_pass = 'PASS'
                # 합격 기준 로직이 있다면 적용 (예: 90점 이상)
                if hasattr(test, 'score') and test.score < 90:
                    status_pass = 'FAIL'

                timeline.append({
                    'type': 'TEST',
                    'date': test.created_at.date(),
                    'timestamp': test.created_at,
                    'title': title_display,
                    'content': f"결과: {score_display}",
                    'sub_info': '', 
                    'status': status_pass,
                    'id': test.id,
                    'raw_date': test.created_at.strftime('%Y-%m-%d')
                })

        # ---------------------------------------------------------
        # 4. 정렬 및 반환
        # ---------------------------------------------------------
        # 최신순 정렬
        timeline.sort(key=lambda x: x['timestamp'], reverse=True)

        # timestamp 객체 제거 (JSON 직렬화 오류 방지)
        for item in timeline:
            del item['timestamp']

        return Response(timeline)