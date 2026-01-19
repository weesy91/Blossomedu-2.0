
import os
import django
import sys
import json
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from rest_framework.test import APIRequestFactory, force_authenticate
from django.contrib.auth import get_user_model
from core.views_api import StudentRegistrationViewSet
from core.models import StaffProfile

User = get_user_model()

def verify_metadata():
    # Setup Teacher
    teacher, _ = User.objects.get_or_create(username='verify_api_teacher', defaults={'is_staff': True})
    if not hasattr(teacher, 'staff_profile'):
        StaffProfile.objects.create(user=teacher, name='VerifyTeacher')

    factory = APIRequestFactory()
    view = StudentRegistrationViewSet.as_view({'get': 'metadata'})
    request = factory.get('/core/api/v1/registration/student/metadata/')
    force_authenticate(request, user=teacher)
    
    response = view(request)
    if response.status_code == 200:
        classes = response.data.get('classes', [])
        print(f"Total Classes: {len(classes)}")
        if len(classes) > 0:
            print("First Class Sample:", json.dumps(classes[0], indent=2, ensure_ascii=False))
            
            # Check for types
            types = set(c['type'] for c in classes)
            print(f"Class Types Found: {types}")
            
            # Check for days
            days = set(c['day'] for c in classes)
            print(f"Days Found: {days}")

        # Check Branches
        branches = response.data.get('branches', [])
        print(f"Total Branches: {len(branches)}")
        if len(branches) > 0:
            print("Branches:", json.dumps(branches, indent=2, ensure_ascii=False))
    else:
        print(f"Error: {response.status_code} {response.data}")

if __name__ == '__main__':
    verify_metadata()
