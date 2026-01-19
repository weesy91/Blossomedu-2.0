import os
import django
from django.conf import settings

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from academy.models import Student

def check_class_times():
    students = Student.objects.all()
    print(f"Total students: {students.count()}")
    
    for student in students:
        if student.class_times:
            print(f"Student: {student.name}, Class Times: {student.class_times}")
        else:
            # print(f"Student: {student.name} has no class times")
            pass

if __name__ == '__main__':
    check_class_times()
