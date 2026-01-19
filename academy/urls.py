from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views_api import AssignmentViewSet, AttendanceViewSet, ClassLogViewSet, TemporaryScheduleViewSet, TextbookViewSet

router = DefaultRouter()
router.register(r'assignments', AssignmentViewSet, basename='assignment')
router.register(r'attendances', AttendanceViewSet, basename='attendance')
router.register(r'class-logs', ClassLogViewSet, basename='classlogs')
router.register(r'schedules', TemporaryScheduleViewSet, basename='schedules')
router.register(r'textbooks', TextbookViewSet, basename='textbook')

urlpatterns = [
    path('api/v1/', include(router.urls)),
]