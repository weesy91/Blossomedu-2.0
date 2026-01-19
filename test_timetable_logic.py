
import os
import django
import sys
import json
from datetime import date
from rest_framework.test import APIRequestFactory, force_authenticate
from django.contrib.auth import get_user_model

sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from core.views_api import StudentRegistrationViewSet
from core.models import StudentProfile, ClassTime, StaffProfile

User = get_user_model()

def test_slot_locking():
    # 1. Setup Data
    print("Setting up test data...")
    # Get or create Teacher
    teacher, _ = User.objects.get_or_create(username='test_teacher_lock', defaults={'is_staff': True})
    if not hasattr(teacher, 'staff_profile'):
        StaffProfile.objects.create(user=teacher, name='LockTestTeacher', is_syntax_teacher=True)
    teacher.staff_profile.is_syntax_teacher = True
    teacher.staff_profile.save()
    
    # Get a Syntax Class
    syntax_class = ClassTime.objects.filter(class_type='SYNTAX').first()
    if not syntax_class:
        print("FAIL: No Syntax class found.")
        return

    print(f"Target Class: {syntax_class}")

    # 2. Register Student (Assign to this class) -- Manual DB creation for speed
    student_user, _ = User.objects.get_or_create(username='test_student_lock')
    if not hasattr(student_user, 'profile'):
        StudentProfile.objects.create(user=student_user, name='LockStudent', base_grade=7)
    
    profile = student_user.profile
    profile.syntax_teacher = teacher
    profile.syntax_class = syntax_class
    profile.save()
    
    print(f"Assigned Student to Teacher {teacher.id} and Class {syntax_class.id}")

    # 3. Call Metadata API
    factory = APIRequestFactory()
    view = StudentRegistrationViewSet.as_view({'get': 'metadata'})
    request = factory.get('/core/api/v1/registration/student/metadata/')
    force_authenticate(request, user=teacher)
    
    response = view(request)
    print(f"API Response Status: {response.status_code}")
    
    if response.status_code == 200:
        booked = response.data.get('booked_syntax_slots', [])
        print(f"Booked Slots: {booked}")
        
        # Verify
        is_locked = any(
            s['syntax_teacher_id'] == teacher.id and s['syntax_class_id'] == syntax_class.id 
            for s in booked
        )
        
        if is_locked:
            print("PASS: Slot is correctly reported as booked.")
        else:
            print("FAIL: Slot missing from booked list.")
    else:
        print(f"Error: {response.data}")

    # Cleanup
    student_user.delete()
    # teacher.delete() # Keep teacher for manual test if needed

if __name__ == '__main__':
    test_slot_locking()
