from rest_framework import viewsets, permissions, status
from rest_framework.response import Response
from rest_framework.decorators import action
from .models import MonthlyReport, ReportShare
from .serializers import ReportShareSerializer
from django.utils import timezone
import datetime

class ReportShareViewSet(viewsets.ModelViewSet):
    """
    성적표 공유 링크 관리 API
    """
    serializer_class = ReportShareSerializer
    permission_classes = [permissions.IsAuthenticated] # 선생님만 접근 가능하게

    def get_queryset(self):
        # 내가 생성한 링크들만
        return ReportShare.objects.all() 

    @action(detail=False, methods=['post'])
    def generate(self, request):
        student_id = request.data.get('student_id')
        if not student_id:
            return Response({'error': 'student_id required'}, status=status.HTTP_400_BAD_REQUEST)
        
        # 유효기간 7일
        expires_at = timezone.now() + datetime.timedelta(days=7)
        
        share_link = ReportShare.objects.create(
            student_id=student_id,
            expires_at=expires_at
        )
        
        serializer = self.get_serializer(share_link)
        return Response(serializer.data, status=status.HTTP_201_CREATED)

class MonthlyReportViewSet(viewsets.ReadOnlyModelViewSet):
    """
    월간 성적표 조회 API (JSON)
    """
    from .serializers import MonthlyReportSerializer
    serializer_class = MonthlyReportSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, 'profile'):
            return MonthlyReport.objects.filter(student=user.profile).order_by('-year', '-month')
        return MonthlyReport.objects.none()
