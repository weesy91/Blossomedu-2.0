
import os
import django
import sys
from datetime import datetime, timedelta

sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from core.models import ClassTime

def generate_slots():
    # 0. Clear Student References (To prevent ProtectedError/IntegrityError)
    print("Clearing student schedule references...")
    try:
        from core.models import StudentProfile
        StudentProfile.objects.all().update(
            syntax_class=None,
            reading_class=None, 
            extra_class=None
        )
    except Exception as e:
        print(f"Warning clearing profiles: {e}")

    # 1. Clear existing
    print("Clearing existing classtimes...")
    ClassTime.objects.all().delete()
    
    days = list(ClassTime.DayChoices.choices) # [('Mon', '월요일'), ...]
    
    # 2. Syntax Slots (1:1, 80 min total but 40min starts)
    # Morning: 09:00 ~ 12:20 (End time is start + 80min? No, slot is just start time)
    # The user said: "Timetable is ... 40 min intervals"
    # Morning: 09:00, 09:40, 10:20, 11:00, 11:40, 12:20 (Last start?)
    # "12:20까지... 그리고 13:20부터" -> implies 12:20 is the last slot or end of slot?
    # "9시부터 40분 간격으로 12시 20분까지" usually means 12:20 is the limit.
    # If 12:20 is a START time, then it ends at 13:40, which overlaps lunch (12:20-13:20?).
    # Usually "Until 12:20" means the block 11:40-12:20 ends at 12:20.
    # But let's assume 12:20 is the last start time for now, or 12:20 is the END of the morning block.
    # Re-reading: "9시부터 ... 12시 20분까지" -> Start times: 09:00, 09:40, 10:20, 11:00, 11:40. (Ends at 12:20).
    # Then "13:20부터 20:40까지" -> Start times: 13:20, 14:00 ... 
    
    # Let's be safe: 12:20 is the END of the morning session.
    # Morning Starts: 09:00, 09:40, 10:20, 11:00, 11:40. (5 slots)
    # Afternoon Starts: 13:20, 14:00, 14:40 ... until 20:40 is the END of the day?
    # Or 20:40 is the last start? "20:40까지 ... 40분 간격으로 있음" usually means 20:40 is the limit.
    # Let's assume start times up to 20:00 (ending 20:40) or starts until 20:40?
    # Context: Academies often run late.
    # Let's check intervals.
    
    syntax_starts = []
    # Morning
    t = datetime.strptime("09:00", "%H:%M")
    end_morning = datetime.strptime("12:20", "%H:%M")
    while t < end_morning: # If 12:20 is end, then strict less
        syntax_starts.append(t)
        t += timedelta(minutes=40)
        
    # Afternoon
    t = datetime.strptime("13:20", "%H:%M")
    # Afternoon
    t = datetime.strptime("13:20", "%H:%M")
    end_night = datetime.strptime("21:00", "%H:%M") # [FIX] Last start 20:40, so stop before 21:20
    while t < end_night: 
        syntax_starts.append(t)
        t += timedelta(minutes=40)
        
    # 3. Reading Slots (1:N, 90 mins)
    # 09:00 ~ every 30 mins until 20:30
    reading_starts = []
    t = datetime.strptime("09:00", "%H:%M")
    end_reading = datetime.strptime("20:30", "%H:%M") 
    while t <= end_reading:
        reading_starts.append(t)
        t += timedelta(minutes=30)

    count = 0
    for day_code, day_name in days:
        # Create Syntax
        for start in syntax_starts:
            end = start + timedelta(minutes=80) 
            ClassTime.objects.create(
                day=day_code,
                start_time=start.time(),
                end_time=end.time(),
                class_type='SYNTAX',
                name=f"구문 {start.strftime('%H:%M')}"
            )
            count += 1
            
        # Create Reading
        for start in reading_starts:
            end = start + timedelta(minutes=90)
            ClassTime.objects.create(
                day=day_code,
                start_time=start.time(),
                end_time=end.time(),
                class_type='READING',
                name=f"독해 {start.strftime('%H:%M')}"
            )
            count += 1
            
        # Create Mock (Same as Reading)
        for start in reading_starts:
            end = start + timedelta(minutes=90) # Assuming 90 mins like Reading
            ClassTime.objects.create(
                day=day_code,
                start_time=start.time(),
                end_time=end.time(),
                class_type='MOCK',
                name=f"모의고사 {start.strftime('%H:%M')}"
            )
            count += 1
            
    print(f"Successfully generated {count} ClassTime slots across 7 days.")

if __name__ == '__main__':
    generate_slots()
