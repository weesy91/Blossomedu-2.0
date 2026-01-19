from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views_api import ExamResultViewSet

router = DefaultRouter()
router.register(r'results', ExamResultViewSet, basename='result')

urlpatterns = [
    path('api/v1/', include(router.urls)),
]