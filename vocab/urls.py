from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views_api import VocabViewSet, TestViewSet, SearchWordViewSet, WordViewSet, PublisherViewSet, RankingEventViewSet

router = DefaultRouter()
router.register(r'books', VocabViewSet, basename='book')
router.register(r'publishers', PublisherViewSet, basename='publisher')
router.register(r'events', RankingEventViewSet, basename='event')
router.register(r'tests', TestViewSet, basename='test')
router.register(r'words', WordViewSet, basename='word')
router.register(r'search', SearchWordViewSet, basename='search')

urlpatterns = [
    path('api/v1/', include(router.urls)),
]
