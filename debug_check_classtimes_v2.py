import os
import django
from django.conf import settings
import json

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from core.models import StudentProfile

def check_class_times():
    students = StudentProfile.objects.all()
    print(f"Total students: {students.count()}")
    
    for student in students:
        if student.class_times:
            print(f"Student: {student.name}")
            print(f"  Raw Value: {student.class_times}")
            print(f"  Type: {type(student.class_times)}")
            
            # JSONField라면 이미 파싱된 상태
            val = student.class_times
            if isinstance(val, str):
                try:
                    val = json.loads(val)
                    print(f"  Parsed JSON: {val}")
                except:
                    print(f"  Raw string (not JSON): {val}")
            
            if isinstance(val, list):
                print(f"  List length: {len(val)}")
                if len(val) > 0:
                    print(f"  First item: {val[0]}")
                    print(f"  First item keys: {val[0].keys() if isinstance(val[0], dict) else 'Not dict'}")
        else:
            pass

if __name__ == '__main__':
    check_class_times()
