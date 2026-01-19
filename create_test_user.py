import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth.models import User
from rest_framework.authtoken.models import Token
from core.models import StaffProfile, Branch

def create_test_teacher():
    username = "test_teacher"
    password = "password123!"
    
    # 1. Create User
    user, created = User.objects.get_or_create(username=username)
    user.set_password(password)
    user.is_staff = True
    user.first_name = "테스트선생님"
    user.save()
    
    if created:
        print(f"Created user: {username}")
    else:
        print(f"Updated user: {username}")

    # 2. Create Token
    token, _ = Token.objects.get_or_create(user=user)
    print(f"Token: {token.key}")

    # 3. Create Branch (if not exists)
    branch, _ = Branch.objects.get_or_create(name="서울본점")
    print(f"Branch: {branch.name}")
    
    # 3-1. Create Sample Schools (for Dropdown test)
    from core.models import School
    school1, _ = School.objects.get_or_create(name="테스트고등학교")
    school1.branches.add(branch)
    
    school2, _ = School.objects.get_or_create(name="서울고등학교")
    school2.branches.add(branch)
    
    print("Sample Schools created.")

    # 4. Create StaffProfile
    profile, _ = StaffProfile.objects.get_or_create(user=user)
    profile.branch = branch
    profile.position = "T" # Teacher
    profile.save()
    print("Staff Profile linked to Branch.")

if __name__ == "__main__":
    create_test_teacher()
