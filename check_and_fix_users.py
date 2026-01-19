
import os
import django
from django.conf import settings

# Setup Django Environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth.models import User
from core.models import StudentProfile, StaffProfile

def check_and_fix_users():
    print("--- Checking Test Users ---")
    
    # 1. Check test_student
    student, created_s = User.objects.get_or_create(username='test_student')
    if created_s:
        print("[INFO] Created 'test_student'")
        student.set_password('password123!')
        student.save()
        # Ensure profile exists
        if not hasattr(student, 'profile'):
             # Need a dummy branch
             from core.models import Branch
             branch, _ = Branch.objects.get_or_create(name="Test Branch")
             StudentProfile.objects.create(user=student, name="Test Student", branch=branch)
    else:
        print("[INFO] 'test_student' exists. Resetting password to 'password123!'")
        student.set_password('password123!')
        student.save()
        
    # 2. Check test_teacher
    teacher, created_t = User.objects.get_or_create(username='test_teacher')
    if created_t:
        print("[INFO] Created 'test_teacher'")
        teacher.set_password('password123!')
        teacher.save()
        if not hasattr(teacher, 'staff_profile'):
            StaffProfile.objects.create(user=teacher, name="Test Teacher", position="Teacher")
    else:
        print("[INFO] 'test_teacher' exists. Resetting password to 'password123!'")
        teacher.set_password('password123!')
        teacher.save()
        # Ensure user type is handled (backend likely relies on profile existence)
        if not hasattr(teacher, 'staff_profile'):
             StaffProfile.objects.create(user=teacher, name="Test Teacher", position="Teacher")

    print("--- Users Ready ---")

if __name__ == '__main__':
    check_and_fix_users()
