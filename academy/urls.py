from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views_api import AssignmentViewSet, AttendanceViewSet, ClassLogViewSet, TemporaryScheduleViewSet, TextbookViewSet

router = DefaultRouter()
router.register(r'assignments', AssignmentViewSet, basename='assignment')
router.register(r'attendances', AttendanceViewSet, basename='attendance')
router.register(r'class-logs', ClassLogViewSet, basename='classlogs')
router.register(r'schedules', TemporaryScheduleViewSet, basename='schedules')
router.register(r'textbooks', TextbookViewSet, basename='textbook')

from .views.log_search import StudentLogSearchView
from .views.management import DailyStudentStatusView
from .views.report import StudentReportViewSet

report_router = DefaultRouter()
report_router.register(r'reports', StudentReportViewSet, basename='report')

urlpatterns = [
    path('api/v1/', include(router.urls)),
    path('api/v1/logs/search/', StudentLogSearchView.as_view(), name='log-search'),
    path('api/v1/daily-status/', DailyStudentStatusView.as_view(), name='daily-status'),
    path('api/v1/', include(report_router.urls)),
]