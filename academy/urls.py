from django.urls import path
from . import views

app_name = 'academy'

urlpatterns = [
    path('management/', views.class_management, name='class_management'),
    path('kiosk/', views.attendance_kiosk, name='kiosk'),
    
    # [NEW] 일지 작성 페이지 (스케줄 ID를 가지고 이동)
    path('log/create/<int:schedule_id>/', views.create_class_log, name='create_class_log'),
    
    # [원장님용] 일일 총괄 대시보드
    path('director/dashboard/', views.director_dashboard, name='director_dashboard'),
    path('vice/dashboard/', views.vice_dashboard, name='vice_dashboard'),
    path('schedule/change/<int:student_id>/', views.schedule_change, name='schedule_change'),
    path('api/availability/', views.check_availability, name='check_availability'),
    path('api/admin/teacher-schedule/', views.get_occupied_times, name='get_occupied_times'),
]