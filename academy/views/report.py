from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from academy.models import StudentReport, Attendance, ClassLog, AssignmentTask
from vocab.models import TestResult # [FIX] Import from correct app
from academy.serializers import StudentReportSerializer
from django.utils import timezone
from datetime import timedelta
import json

class StudentReportViewSet(viewsets.ModelViewSet):
    queryset = StudentReport.objects.all()
    serializer_class = StudentReportSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, 'profile'):
            return StudentReport.objects.filter(student=user.profile).order_by('-created_at')
        if user.is_staff:
            # TODO: Filter by branch/managed students properly
            return StudentReport.objects.all().order_by('-created_at')
        return StudentReport.objects.none()

    @action(detail=False, methods=['post'])
    def generate(self, request):
        """
        성적표 생성 (데이터 집계 및 스냅샷 저장)
        Params: student_id, title, start_date, end_date, teacher_comment
        """
        student_id = request.data.get('student_id')
        start_date_str = request.data.get('start_date')
        end_date_str = request.data.get('end_date')
        title = request.data.get('title', '학습 리포트')
        comment = request.data.get('teacher_comment', '')

        if not all([student_id, start_date_str, end_date_str]):
            return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

        # 1. 데이터 집계
        snapshot = self._aggregate_data(student_id, start_date_str, end_date_str)

        # 2. 리포트 생성/갱신 (같은 기간/제목이면 갱신?) -> 일단 무조건 생성
        report = StudentReport.objects.create(
            student_id=student_id,
            teacher=request.user,
            title=title,
            start_date=start_date_str,
            end_date=end_date_str,
            data_snapshot=snapshot,
            teacher_comment=comment
        )

        return Response(self.get_serializer(report).data)

    @action(detail=False, methods=['post'])
    def preview(self, request):
        """
        성적표 미리보기 (저장 안함)
        """
        student_id = request.data.get('student_id')
        start_date_str = request.data.get('start_date')
        end_date_str = request.data.get('end_date')

        if not all([student_id, start_date_str, end_date_str]):
            return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

        # 1. 데이터 집계
        snapshot = self._aggregate_data(student_id, start_date_str, end_date_str)
        return Response(snapshot)

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny], url_path='public/(?P<uuid>[^/.]+)')
    def public_view(self, request, uuid=None):
        """
        공개 링크 조회 (로그인 불필요)
        """
        try:
            report = StudentReport.objects.get(uuid=uuid)
        except StudentReport.DoesNotExist:
            return Response({'error': 'Not found'}, status=status.HTTP_404_NOT_FOUND)
        
        return Response(self.get_serializer(report).data)

    def _aggregate_data(self, student_id, start, end):
        """
        지정 기간 동안의 모든 학습 데이터 집계
        """
        # (1) 출결
        attendances = Attendance.objects.filter(
            student_id=student_id, 
            date__range=[start, end]
        ).values('date', 'status', 'check_in_time')
        
        # (2) 단어 시험 (상세 정보 추가)
        from vocab.models import TestResult
        vocab_tests = TestResult.objects.filter(
            student_id=student_id,
            created_at__date__range=[start, end]
        ).select_related('book').values(
            'created_at', 'score', 'total_count', 'wrong_count', 
            'book__title', 'test_range'
        )

        # (3) 과제 (피드백 포함)
        # AssignmentTask -> Submission (OneToOne)
        assignments_qs = AssignmentTask.objects.filter(
            student_id=student_id,
            due_date__date__range=[start, end]
        ).select_related('submission', 'related_textbook', 'related_vocab_book')
        
        assignments = []
        for a in assignments_qs:
            feedback = ''
            status = '미제출'
            if hasattr(a, 'submission'):
                feedback = a.submission.teacher_comment
                status = a.submission.get_status_display()
            elif a.is_completed:
                status = '완료'
            
            assignments.append({
                'title': a.title,
                'due_date': a.due_date,
                'is_completed': a.is_completed,
                'assignment_type': a.get_assignment_type_display(),
                'status': status,
                'feedback': feedback,
            })

        # (4) 수업 일지 (진도 및 숙제 포함)
        logs_qs = ClassLog.objects.filter(
            student_id=student_id,
            date__range=[start, end]
        ).prefetch_related('entries', 'entries__textbook', 'entries__wordbook', 'generated_assignments')
        
        logs = []
        for l in logs_qs:
            # Entries (진도)
            details = []
            for e in l.entries.all():
                book_name = e.textbook.title if e.textbook else (e.wordbook.title if e.wordbook else '기타')
                details.append(f"{book_name} ({e.progress_range}) - {e.score or '-'}")
            
            # Homeworks
            homeworks = [t.title for t in l.generated_assignments.all()]
            
            logs.append({
                'date': l.date,
                'subject': l.get_subject_display(), # '구문' -> '1:1 구문수업' logic needed? frontend or here? 
                # Let's override here if easy, but get_subject_display comes from choices.
                # Use raw 'subject' code and map in frontend is safer for i18n/consistency.
                'subject_code': l.subject, 
                'comment': l.comment,
                'teacher_comment': l.teacher_comment,
                'details': details,
                'homeworks': homeworks,
            })

        # 통계 계산
        total_days = len(attendances)
        present_days = sum(1 for a in attendances if a['status'] == 'PRESENT')
        
        vocab_avg = 0
        if vocab_tests:
            vocab_avg = sum(t['score'] for t in vocab_tests) / len(vocab_tests)

        # [FIX] JSON Serialization: Convert datetime/date objects to string
        def serialize_list(data_list):
            new_list = []
            for item in data_list:
                new_item = item.copy() if isinstance(item, dict) else item
                if isinstance(new_item, dict):
                    for key, value in new_item.items():
                        if hasattr(value, 'isoformat'):
                            new_item[key] = value.isoformat()
                new_list.append(new_item)
            return new_list

        return {
            'stats': {
                'attendance_rate': (present_days / total_days * 100) if total_days > 0 else 0,
                'vocab_avg': round(vocab_avg, 1),
                'assignment_count': len(assignments),
                'assignment_completed': sum(1 for a in assignments if a['is_completed']),
            },
            'attendance': serialize_list(list(attendances)),
            'vocab': serialize_list(list(vocab_tests)),
            'assignments': serialize_list(assignments),
            'logs': serialize_list(logs),
        }
