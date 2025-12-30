from django.urls import path
from . import views

app_name = 'exam'

urlpatterns = [
    # 이미지 대량 업로드 페이지
    path('upload/images/', views.upload_images_bulk, name='upload_images'),
    path('create/', views.create_test_paper, name='create_test_paper'),
    path('print/<int:paper_id>/', views.print_test_paper, name='print_test_paper'),
    path('api/students/', views.get_students_by_teacher, name='get_students_by_teacher'),
]