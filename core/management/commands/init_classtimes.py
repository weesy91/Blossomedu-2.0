from django.core.management.base import BaseCommand
from core.models import ClassTime
from datetime import time

class Command(BaseCommand):
    help = '학원 시간표(구문 40분 간격 / 독해 30분 간격)를 자동으로 생성합니다.'

    def add_minutes(self, t, minutes):
        """time 객체에 분을 더한 새로운 time 객체 반환"""
        total_minutes = t.hour * 60 + t.minute + minutes
        new_hour = (total_minutes // 60) % 24
        new_minute = total_minutes % 60
        return time(new_hour, new_minute)

    def create_class_times(self, day_code, day_name, start_time, limit_time, interval_minutes, subject_name):
        """수업 시간표를 생성하는 helper 함수"""
        current = start_time
        count = 0
        while current <= limit_time:
            end_time = self.add_minutes(current, interval_minutes)
            # 반 이름: "[구문] 월요일 16:00" 형식 (시작 시간 표시)
            name = f"[{subject_name}] {day_name} {current.strftime('%H:%M')}"
            
            # get_or_create로 중복 방지 (day, start_time, end_time으로 중복 체크)
            obj, created = ClassTime.objects.get_or_create(
                day=day_code,
                start_time=current,
                end_time=end_time,
                defaults={'name': name}
            )
            
            if created:
                count += 1
                self.stdout.write(f'  ✓ 생성: {name}')
            
            # 다음 시간으로 이동 (간격만큼)
            current = self.add_minutes(current, interval_minutes)
        
        return count

    def handle(self, *args, **kwargs):
        # 요일 매핑: 0=월요일, 1=화요일, ..., 6=일요일
        day_map = {
            0: 'Mon',  # 월요일
            1: 'Tue',  # 화요일
            2: 'Wed',  # 수요일
            3: 'Thu',  # 목요일
            4: 'Fri',  # 금요일
            5: 'Sat',  # 토요일
            6: 'Sun',  # 일요일
        }
        
        # 요일 한글명
        day_names = {
            0: '월요일',
            1: '화요일',
            2: '수요일',
            3: '목요일',
            4: '금요일',
            5: '토요일',
            6: '일요일',
        }
        
        total_created = 0

        # ==========================================
        # [1] 구문 수업 (간격 40분)
        # ==========================================
        self.stdout.write(self.style.SUCCESS('\n=== 구문 수업 생성 중 ==='))
        
        # 1-1. 구문 평일 (월~금): 16:00 ~ 20:40
        weekdays = [0, 1, 2, 3, 4]  # 월~금
        for day_num in weekdays:
            day_code = day_map[day_num]
            day_name = day_names[day_num]
            count = self.create_class_times(
                day_code, day_name,
                time(16, 0), time(20, 40),
                40, '구문'
            )
            total_created += count

        # 1-2. 구문 주말 (토~일): 오전 09:00 ~ 12:20, 오후 13:20 ~ 18:00
        weekends = [5, 6]  # 토~일
        for day_num in weekends:
            day_code = day_map[day_num]
            day_name = day_names[day_num]
            
            # 오전: 09:00 ~ 12:20
            count = self.create_class_times(
                day_code, day_name,
                time(9, 0), time(12, 20),
                40, '구문'
            )
            total_created += count
            
            # 오후: 13:20 ~ 18:00
            count = self.create_class_times(
                day_code, day_name,
                time(13, 20), time(18, 0),
                40, '구문'
            )
            total_created += count

        # ==========================================
        # [2] 독해 수업 (간격 30분)
        # ==========================================
        self.stdout.write(self.style.SUCCESS('\n=== 독해 수업 생성 중 ==='))

        # 2-1. 독해 평일 (월~금): 16:00 ~ 20:30
        for day_num in weekdays:
            day_code = day_map[day_num]
            day_name = day_names[day_num]
            count = self.create_class_times(
                day_code, day_name,
                time(16, 0), time(20, 30),
                30, '독해'
            )
            total_created += count

        # 2-2. 독해 주말 (토~일): 09:00 ~ 18:00 (점심시간 브레이크 없음)
        for day_num in weekends:
            day_code = day_map[day_num]
            day_name = day_names[day_num]
            count = self.create_class_times(
                day_code, day_name,
                time(9, 0), time(18, 0),
                30, '독해'
            )
            total_created += count

        self.stdout.write(self.style.SUCCESS(f'\n✅ 완료!'))
        self.stdout.write(f'   새로 생성된 시간표: {total_created}개')
        self.stdout.write(f'   전체 시간표 수: {ClassTime.objects.count()}개')