from rest_framework import viewsets, permissions
from .models import ExamResult
from .serializers import ExamResultSerializer

class ExamResultViewSet(viewsets.ReadOnlyModelViewSet):
    """
    월말평가 결과 조회 API
    """
    serializer_class = ExamResultSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, 'profile'):
            return ExamResult.objects.filter(student=user.profile).order_by('-date')
        return ExamResult.objects.none()