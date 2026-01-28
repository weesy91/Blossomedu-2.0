from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import ClassTime

@receiver(post_save, sender=ClassTime)
def mirror_reading_to_mock(sender, instance, created, **kwargs):
    """
    ClassTime이 생성/수정될 때, 'READING' 타입이면 자동으로 'MOCK' 타입도 생성.
    """
    if instance.class_type == 'READING':
        # MOCK 스케줄 이름 표준화
        time_str = instance.start_time.strftime('%H:%M')
        mock_name = f"모의고사 {time_str}"
        
        # MOCK 존재 여부 확인
        exists = ClassTime.objects.filter(
            branch=instance.branch,
            day=instance.day,
            start_time=instance.start_time,
            class_type='MOCK'
        ).exists()
        
        if not exists:
            ClassTime.objects.create(
                branch=instance.branch,
                name=mock_name,
                day=instance.day,
                start_time=instance.start_time,
                end_time=instance.end_time,
                class_type='MOCK'
            )
            print(f"[Signal] Auto-created MOCK schedule: {mock_name}")

from .models import Branch
from datetime import datetime, timedelta

@receiver(post_save, sender=Branch)
def create_schedules_for_new_branch(sender, instance, created, **kwargs):
    """
    지점(Branch)이 새로 생성되면, 자동으로 기본 시간표(구문, 독해)를 생성합니다.
    (독해가 생성되면 위 mirror 신호에 의해 모의고사도 자동 생성됨)
    """
    if created:
        print(f"[Signal] Generating schedules for new branch: {instance.name}")
        days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        
        # 1. Syntax Logic (40 min intervals)
        # Morning: 09:00 ~ 12:20 (Last start 11:40)
        # Afternoon: 13:20 ~ 21:20 (Last start 20:40)
        syntax_starts = []
        
        # Morning
        t = datetime.strptime("09:00", "%H:%M")
        end_morning = datetime.strptime("12:20", "%H:%M")
        while t < end_morning:
            syntax_starts.append(t)
            t += timedelta(minutes=40)
            
        # Afternoon
        t = datetime.strptime("13:20", "%H:%M")
        end_night = datetime.strptime("21:20", "%H:%M") # Covers up to 20:40 start
        while t < end_night:
            syntax_starts.append(t)
            t += timedelta(minutes=40)

        # 2. Reading Logic (30 min intervals)
        # 09:00 ~ 20:30 triggers
        reading_starts = []
        t = datetime.strptime("09:00", "%H:%M")
        end_reading = datetime.strptime("20:30", "%H:%M")
        while t <= end_reading:
            reading_starts.append(t)
            t += timedelta(minutes=30)
            
        for day_code in days:
            # Create Syntax
            for start in syntax_starts:
                end = start + timedelta(minutes=80)
                ClassTime.objects.create(
                    branch=instance,
                    day=day_code,
                    start_time=start.time(),
                    end_time=end.time(),
                    class_type='SYNTAX',
                    name=f"구문 {start.strftime('%H:%M')}"
                )
                
            # Create Reading (Will trigger Mock creation)
            for start in reading_starts:
                end = start + timedelta(minutes=90)
                ClassTime.objects.create(
                    branch=instance,
                    day=day_code,
                    start_time=start.time(),
                    end_time=end.time(),
                    class_type='READING',
                    name=f"독해 {start.strftime('%H:%M')}"
                )

