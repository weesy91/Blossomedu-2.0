import sys
import os
import django

# Setup Django environment
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.utils import timezone


from django.contrib.auth import get_user_model

def verify_student_detail():
    # Deferred imports to ensure AppRegistry is ready
    User = get_user_model()
    from core.models import StudentProfile, StaffProfile, ClassTime, Branch
    from core.serializers import StudentProfileSerializer
    from rest_framework.test import APIRequestFactory

    print("=== Verifying Student Detail API Serializer ===")

    # 1. Setup Data
    # Teacher
    teacher_user, _ = User.objects.get_or_create(username='detail_test_teacher')
    teacher_profile, _ = StaffProfile.objects.get_or_create(user=teacher_user, defaults={'name': 'Detail Teacher', 'is_syntax_teacher': True})
    
    # ClassTime
    classtime, _ = ClassTime.objects.get_or_create(
        day='Mon', 
        start_time='14:00', 
        class_type='SYNTAX',
        defaults={'end_time': '15:20'}
    )

    # Student
    student_user, _ = User.objects.get_or_create(username='detail_test_student')
    student_profile, _ = StudentProfile.objects.get_or_create(user=student_user, defaults={'name': 'Detail Student'})

    # Assign Class
    student_profile.syntax_teacher = teacher_user
    student_profile.syntax_class = classtime
    student_profile.save()
    
    # 2. Serialize
    serializer = StudentProfileSerializer(student_profile)
    data = serializer.data
    
    print("\n[Serialized Data Keys]:")
    print(data.keys())
    
    print("\n[Timetable Data]:")
    print(f"Syntax Teacher: {data.get('syntax_teacher')}")
    print(f"Syntax Class: {data.get('syntax_class')}")
    
    # 3. Verify
    if 'syntax_teacher' in data and data['syntax_teacher'] == teacher_user.id:
        print("\n[PASS] Syntax Teacher ID present and correct.")
    else:
        print("\n[FAIL] Syntax Teacher ID missing or incorrect.")
        
    if 'syntax_class' in data and data['syntax_class'] == classtime.id:
        print("[PASS] Syntax Class ID present and correct.")
    else:
        print("[FAIL] Syntax Class ID missing or incorrect.")

    # Cleanup
    student_profile.syntax_teacher = None
    student_profile.syntax_class = None
    student_profile.save()

if __name__ == '__main__':
    verify_student_detail()
