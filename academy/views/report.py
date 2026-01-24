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
        
        # (2) 단어 시험 (점수만)
        # Note: TestResult is in vocab app, import needed or string ref?
        # Imported 'from academy.models import TestResult'? No, TestResult is in vocab.models.
        from vocab.models import TestResult
        vocab_tests = TestResult.objects.filter(
            student_id=student_id,
            created_at__date__range=[start, end]
        ).select_related('book').values('created_at', 'score', 'total_count', 'book__title')

        # (3) 과제
        assignments = AssignmentTask.objects.filter(
            student_id=student_id,
            due_date__date__range=[start, end]
        ).values('title', 'due_date', 'is_completed', 'assignment_type')

        # (4) 수업 일지 (코멘트)
        logs = ClassLog.objects.filter(
            student_id=student_id,
            date__range=[start, end]
        ).values('date', 'subject', 'comment', 'teacher_comment')

        # 통계 계산
        total_days = len(attendances)
        present_days = sum(1 for a in attendances if a['status'] == 'PRESENT')
        
        vocab_avg = 0
        if vocab_tests:
            vocab_avg = sum(t['score'] for t in vocab_tests) / len(vocab_tests)

        return {
            'stats': {
                'attendance_rate': (present_days / total_days * 100) if total_days > 0 else 0,
                'vocab_avg': round(vocab_avg, 1),
                'assignment_count': len(assignments),
                'assignment_completed': sum(1 for a in assignments if a['is_completed']),
            },
            'attendance': list(attendances),
            'vocab': list(vocab_tests),
            'assignments': list(assignments),
            'logs': list(logs),
        }
