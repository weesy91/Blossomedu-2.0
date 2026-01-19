import os
import django
import sys

sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from core.models import Branch

User = get_user_model()

def fix_branch():
    try:
        user = User.objects.get(username='test_student')
        profile = user.profile
        
        target_branch = Branch.objects.filter(name='서울본점').first()
        if not target_branch:
            print("Error: '서울본점' not found in DB.")
            return

        print(f"Current Branch: {profile.branch}")
        profile.branch = target_branch
        profile.save()
        print(f"Updated Branch to: {profile.branch}")
        
    except Exception as e:
        print(f"Error: {e}")

if __name__ == '__main__':
    fix_branch()
