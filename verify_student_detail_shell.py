from django.contrib.auth import get_user_model
from core.models import StudentProfile, StaffProfile, ClassTime, Branch
from core.serializers import StudentProfileSerializer
from rest_framework.test import APIRequestFactory

def verify():
    print("=== Verifying Student Detail API Serializer ===")
    User = get_user_model()
    
    # 1. Setup Data
    teacher_user, _ = User.objects.get_or_create(username='detail_test_teacher')
    teacher_profile, _ = StaffProfile.objects.get_or_create(user=teacher_user, defaults={'name': 'Detail Teacher', 'is_syntax_teacher': True})
    
    classtime, _ = ClassTime.objects.get_or_create(day='Mon', start_time='14:00', class_type='SYNTAX', defaults={'end_time': '15:20'})

    student_user, _ = User.objects.get_or_create(username='detail_test_student')
    student_profile, _ = StudentProfile.objects.get_or_create(user=student_user, defaults={'name': 'Detail Student'})

    # Assign Class
    student_profile.syntax_teacher = teacher_user
    student_profile.syntax_class = classtime
    student_profile.save()
    
    # 2. Serialize
    serializer = StudentProfileSerializer(student_profile)
    data = serializer.data
    
    print(f"Syntax Teacher: {data.get('syntax_teacher')}")
    print(f"Syntax Class: {data.get('syntax_class')}")
    print(f"Extra Class: {data.get('extra_class')}") 
    
    if data.get('syntax_teacher') == teacher_user.id and data.get('syntax_class') == classtime.id:
        print("[PASS] Timetable IDs present.")
    else:
        print("[FAIL] Timetable IDs missing.")

verify()
