from django.urls import path, include
from . import views, views_api
from rest_framework.routers import DefaultRouter

app_name = 'mock'

router = DefaultRouter()
router.register(r'api/v1/infos', views_api.MockExamInfoViewSet, basename='api-info')
router.register(r'api/v1/results', views_api.MockExamViewSet, basename='api-result')

urlpatterns = [
    path('list/', views.student_list, name='student_list'),
    path('input/<int:student_id>/', views.input_score, name='input_score'),
    path('bulk-upload/', views.bulk_omr_upload, name='bulk_upload'),
    
    # [API]
    path('api/v1/scan/', views_api.OMRScanView.as_view(), name='api-scan'),
    path('api/v1/confirm/', views_api.ScoreConfirmView.as_view(), name='api-confirm'),
    path('', include(router.urls)),
]
