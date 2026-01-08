from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import datetime, timedelta
from core.models import StudentProfile
from academy.models import Attendance
from academy.utils import get_today_class_start_time
# from utils.aligo import send_alimtalk  <-- 아직 파일 없으면 주석 유지

class Command(BaseCommand):
    help = '수업 시작 시간이 지났는데 등원하지 않은 학생을 찾아 자동으로 결석 처리하고 알림을 보냅니다.'

    def handle(self, *args, **options):
        now = timezone.now()
        today = now.date()
        
        students = StudentProfile.objects.all() 
        check_count = 0
        absent_created = 0

        for student in students:
            if Attendance.objects.filter(student=student, date=today).exists():
                continue

            start_time = get_today_class_start_time(student)
            if start_time is None:
                continue

            # [수정된 부분] 
            # 1. 일단 단순 시간으로 합칩니다.
            class_start_dt = datetime.combine(today, start_time)
            
            # 2. 만약 now(현재시간)가 '타임존'을 달고 있다면, 수업시간에도 똑같이 달아줍니다.
            # (이 코드가 없으면 비교할 때 에러가 납니다)
            if timezone.is_aware(now):
                class_start_dt = timezone.make_aware(class_start_dt)

            # 4. 비교 시작
            if now > class_start_dt:
                diff = now - class_start_dt
                minutes_passed = diff.total_seconds() / 60
                
                if minutes_passed >= 40:
                    Attendance.objects.create(
                        student=student,
                        date=today,
                        status='ABSENT',
                        memo='시스템 자동 결석 처리 (40분 경과)'
                    )
                    self.stdout.write(self.style.ERROR(f"❌ [결석 처리] {student.name} (수업: {start_time}, {int(minutes_passed)}분 지남)"))
                    absent_created += 1

                    if student.send_attendance_alarm:
                        # send_alimtalk(...) # 나중에 주석 해제
                        pass
                
                elif minutes_passed >= 10:
                    pass

        if absent_created > 0:
            self.stdout.write(self.style.SUCCESS(f"=== 결과: {absent_created}명 결석 처리 완료 ==="))