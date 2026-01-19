# reports/urls.py
from django.urls import path, include
from . import views
from rest_framework.routers import DefaultRouter
from .views_api import ReportShareViewSet, MonthlyReportViewSet

router = DefaultRouter()
router.register(r'share', ReportShareViewSet, basename='report_share')
router.register(r'monthly', MonthlyReportViewSet, basename='monthly_report')

app_name = 'reports'

urlpatterns = [
    # 선생님이 성적표 생성하는 URL (버튼 클릭용)
    path('dashboard/', views.report_dashboard, name='dashboard'),
    path('create/<int:student_id>/', views.create_monthly_report, name='create'),
    path('view/<uuid:access_code>/', views.report_view, name='view'),
    path('share/view/<uuid:uuid>/', views.shared_report_view, name='shared_view'), # [NEW] 공유 링크용 View
    path('send/<int:report_id>/', views.send_report_notification, name='send_notification'),
    
    # [API]
    path('api/v1/', include(router.urls)),
]