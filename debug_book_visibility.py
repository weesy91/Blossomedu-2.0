import os
import django
import sys

# Setup Django
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from core.models import StudentProfile
from vocab.models import WordBook
from django.db.models import Q

User = get_user_model()

def check_visibility():
    print("=== 1. Checking Test Student Profile ===")
    try:
        user = User.objects.get(username='test_student')
        profile = user.profile
        print(f"User: {user.username}")
        print(f"Branch: {profile.branch}")
        print(f"School: {profile.school}")
        print(f"Grade: {profile.current_grade} (Base: {profile.base_grade}, Year: {profile.base_year})")
    except Exception as e:
        print(f"Error finding test_student: {e}")
        return

    print("\n=== 2. Checking All WordBooks ===")
    books = WordBook.objects.all()
    for b in books:
        print(f"Book [{b.id}] '{b.title}'")
        print(f"  - Target Branch: {b.target_branch}")
        print(f"  - Target School: {b.target_school}")
        print(f"  - Target Grade: {b.target_grade}")
        print(f"  - Uploader: {b.uploaded_by}")
    
    print("\n=== 3. Simulating Filter Logic (Updated) ===")
    # Logic from views_api.py (Match 'available' logic)
    
    branch_filter = Q(target_branch__isnull=True) | Q(target_branch=profile.branch)
    school_filter = Q(target_school__isnull=True) | Q(target_school=profile.school)
    grade_filter = Q(target_grade__isnull=True) | Q(target_grade=profile.current_grade)

    qs = WordBook.objects.filter(
        branch_filter & school_filter & grade_filter
    ).exclude(
        subscribers__student=profile
    )
    
    print(f"Final Visible Books for 'available': {[b.title for b in qs]}")
    
    # Also check 'My Books' logic
    print("\n=== 4. Simulating 'My Books' Logic ===")
    my_books_qs = WordBook.objects.filter(subscribers__student=profile)
    print(f"Visible Books for 'my_books': {[b.title for b in my_books_qs]}")

if __name__ == '__main__':
    import sys
    with open('debug_output_2.txt', 'w', encoding='utf-8') as f:
        sys.stdout = f
        check_visibility()
