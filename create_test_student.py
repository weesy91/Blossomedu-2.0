import os
import sys

def create_student():
    # Setup Django
    sys.path.append(os.getcwd())
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    import django
    django.setup()

    from django.contrib.auth import get_user_model
    from core.models import StudentProfile, Branch

    User = get_user_model()
    
    username = 'test_student'
    password = 'password123!'
    
    if User.objects.filter(username=username).exists():
        print(f"User {username} already exists.")
        user = User.objects.get(username=username)
        user.set_password(password)
        user.save()
        print("Password updated.")
    else:
        user = User.objects.create_user(username=username, password=password)
        print(f"User {username} created.")

    # Update Profile
    if hasattr(user, 'profile'):
        profile = user.profile
        profile.name = '테스트학생'
        # Assign a branch if exists
        branch = Branch.objects.first()
        if branch:
            profile.branch = branch
            print(f"Assigned branch: {branch.name}")
        
        profile.save()
        print("Profile updated with name '테스트학생'.")
    else:
        # Check if we need to manually create it (if signal failed or whatever)
        StudentProfile.objects.create(user=user, name='테스트학생')
        print("Created StudentProfile manually.")

if __name__ == '__main__':
    try:
        create_student()
    except Exception as e:
        import traceback
        traceback.print_exc()
        print(f"FAILED: {e}")
