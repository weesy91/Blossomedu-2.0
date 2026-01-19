
import os
import django
import sys
import json
from rest_framework.test import APIRequestFactory, force_authenticate
from django.contrib.auth import get_user_model

# Django Setup
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from core.views_api import StudentRegistrationViewSet
from core.models import StaffProfile

User = get_user_model()

def test_metadata():
    factory = APIRequestFactory()
    view = StudentRegistrationViewSet.as_view({'get': 'metadata'})
    
    # Needs a teacher user
    try:
        user = User.objects.get(username='test_teacher')
    except User.DoesNotExist:
        print("User test_teacher not found, using first staff user")
        user = User.objects.filter(is_staff=True).first()
        
    if not user:
        print("No staff user found!")
        return

    request = factory.get('/core/api/v1/registration/student/metadata/')
    force_authenticate(request, user=user)
    
    response = view(request)
    print(f"Status Code: {response.status_code}")
    if response.status_code == 200:
        data = response.data
        print("Classes Sample:")
        classes = data.get('classes', [])
        if classes:
            print(classes[0])
            if 'day' in classes[0] and 'time' in classes[0]:
                print("PASS: 'day' and 'time' fields present.")
            else:
                print("FAIL: 'day' or 'time' missing.")
        else:
            print("No classes found to verify.")
    else:
        print(f"Error: {response.data}")

if __name__ == '__main__':
    test_metadata()
