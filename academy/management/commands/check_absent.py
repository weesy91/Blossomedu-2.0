from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import datetime, timedelta
from core.models import StudentProfile
from academy.models import Attendance
from academy.utils import get_today_class_start_time

class Command(BaseCommand):
    help = '수업 시작 40분이 지난 미등원 학생을 찾아 자동으로 결석 처리합니다.'

    def handle(self, *args, **kwargs):
        today = timezone.now().date()
        now = datetime.now() # 현재 시간
        
        profiles = StudentProfile.objects.all()
        count = 0

        self.stdout.write(f"[{now}] 자동 결석 체크 시작...")

        for profile in profiles:
            # 1. 오늘 이미 출석 기록이 있는지 확인
            if Attendance.objects.filter(student=profile.user, date=today).exists():
                continue # 이미 기록이 있으면 패스

            # 2. 오늘 수업 시간 가져오기
            start_time = get_today_class_start_time(profile)
            
            if start_time:
                # 3. 수업 시간 + 40분 계산 (결석 확정 시간)
                class_dt = datetime.combine(today, start_time)
                cutoff_dt = class_dt + timedelta(minutes=40)
                
                # 4. 현재 시간이 커트라인(40분)을 지났다면? -> 결석 확정!
                if now > cutoff_dt:
                    Attendance.objects.create(
                        student=profile.user,
                        date=today,
                        status='ABSENT', # 무단 결석
                        memo='시스템 자동 결석 처리' # 누가 했는지 메모 남기기
                    )
                    self.stdout.write(self.style.WARNING(f"❌ {profile.name} 학생 자동 결석 처리됨."))
                    count += 1
        
        self.stdout.write(self.style.SUCCESS(f"완료! 총 {count}명 결석 처리됨."))