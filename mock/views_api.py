from rest_framework import viewsets, permissions
from .models import MockExam
from .serializers import MockExamSerializer

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
