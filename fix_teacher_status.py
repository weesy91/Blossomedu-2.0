
import os
import django
import sys

# Django Setup
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from core.models import StaffProfile

User = get_user_model()

def fix_teacher():
    try:
        user = User.objects.get(username='test_teacher')
        print(f"Found user: {user.username}, Current is_staff: {user.is_staff}")
        
        # 1. Fix is_staff
        if not user.is_staff:
            user.is_staff = True
            user.save()
            print(" -> Updated is_staff to True")
        else:
            print(" -> is_staff is already True")
            
        # 2. Check Profile
        if not hasattr(user, 'staffprofile'):
            print(" -> No StaffProfile found. Creating one...")
            StaffProfile.objects.create(
                user=user,
                phone_number='010-1234-5678',
                name='테스트선생님'
            )
            print(" -> StaffProfile created.")
        else:
            print(" -> StaffProfile exists.")
            
        print("Done.")
        
    except User.DoesNotExist:
        print("User 'test_teacher' does not exist!")

if __name__ == '__main__':
    fix_teacher()
