import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from core.models import StudentProfile

User = get_user_model()

def cleanup():
    print("Checking for Staff users with Student Profiles...")
    staff_users = User.objects.filter(is_staff=True)
    count = 0
    for user in staff_users:
        if hasattr(user, 'profile'):
            print(f"Removing StudentProfile for Staff: {user.username}")
            user.profile.delete()
            count += 1
    
    print(f"Cleanup complete. Removed {count} erroneous StudentProfiles.")

if __name__ == '__main__':
    cleanup()
