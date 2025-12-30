# academy/utils.py

from django.utils import timezone
from .models import TemporarySchedule

def get_today_class_start_time(student_profile):
    """
    오늘 이 학생의 '기준 등원 시간'을 계산하는 공통 함수
    (키오스크와 자동 결석 체크 기능에서 함께 사용)
    """
    today = timezone.now().date()
    today_weekday = today.weekday() # 0:월 ~ 6:일

    # 1. [1순위] 보강/일정 변경 확인
    temp_schedule = TemporarySchedule.objects.filter(
        student=student_profile.user,
        new_date=today
    ).first()
    
    if temp_schedule:
        return temp_schedule.new_start_time

    # 2. [예외] 오늘 수업이 다른 날로 이동했는지 확인
    moved_away = TemporarySchedule.objects.filter(
        student=student_profile.user,
        original_date=today
    ).exists()
    
    if moved_away:
        return None 

    # 3. [2순위] 정규 수업 시간 확인
    start_times = []
    
    # 요일 숫자(0~6)끼리 비교
    if student_profile.syntax_class and student_profile.syntax_class.day == today_weekday:
        start_times.append(student_profile.syntax_class.start_time)
        
    if student_profile.reading_class and student_profile.reading_class.day == today_weekday:
        start_times.append(student_profile.reading_class.start_time)
        
    if start_times:
        return min(start_times) 
        
    return None