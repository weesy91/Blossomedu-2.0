
import os
import django
import sys

sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from core.models import ClassTime

def check_classtimes():
    count = ClassTime.objects.count()
    print(f"Total ClassTimes: {count}")
    
    if count == 0:
        print("No ClassTime data found! Creating defaults...")
        defaults = [
            {'day': 'Mon', 'start_time': '16:00', 'end_time': '18:00', 'name': '구문_월_A반'},
            {'day': 'Wed', 'start_time': '16:00', 'end_time': '18:00', 'name': '독해_수_A반'},
            {'day': 'Fri', 'start_time': '16:00', 'end_time': '18:00', 'name': '특강_금_A반'},
        ]
        for d in defaults:
            ClassTime.objects.create(**d)
            print(f"Created: {d['name']}")
    else:
        for c in ClassTime.objects.all():
            print(f"- {c.name} ({c.day} {c.start_time})")

if __name__ == '__main__':
    check_classtimes()
