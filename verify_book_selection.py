
import os
import django
from django.conf import settings

# Setup Django Environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth.models import User
from core.models import StudentProfile, StaffProfile, Branch
from vocab.models import WordBook, Publisher, PersonalWordBook
from rest_framework.test import APIClient

def run_verification():
    print("--- Starting Book Selection Verification ---")

    # 1. Setup Data
    # Create Publisher
    pub, _ = Publisher.objects.get_or_create(name="Test Publisher")
    
    # Create Staff (Creator)
    staff_user, _ = User.objects.get_or_create(username="test_staff")
    
    # Create a Test WordBook (Target All)
    book1, created1 = WordBook.objects.get_or_create(
        title="General Available Book",
        publisher=pub,
        uploaded_by=staff_user,
        defaults={'target_branch': None}
    )
    
    # Create a Test Student
    student_user, _ = User.objects.get_or_create(username="test_student_book")
    if not hasattr(student_user, 'profile'):
        print("[INFO] Creating StudentProfile...")
        # Need a branch
        branch, _ = Branch.objects.get_or_create(name="Test Branch")
        StudentProfile.objects.create(user=student_user, name="Book Student", branch=branch)
        
    student_profile = student_user.profile
    
    # Ensure Test Student has NO subscriptions initially
    PersonalWordBook.objects.filter(student=student_profile).delete()

    client = APIClient()
    client.force_authenticate(user=student_user)
    print("[OK] Authenticated as Student")

    # 2. Test 'Available' API
    url_available = '/vocab/api/v1/books/available/'
    print(f"Fetching available books from {url_available}...")
    
    response = client.get(url_available)
    if response.status_code != 200:
        print(f"[FAIL] Available API Failed: {response.status_code}")
        return

    data = response.data
    print(f"[INFO] Found {len(data)} available books.")
    
    target_book = next((b for b in data if b['id'] == book1.id), None)
    
    if target_book:
        print(f"[OK] Found target book: {target_book['title']}")
        # Check field names
        if 'total_days' in target_book:
            print(f"[OK] Field 'total_days' exists: {target_book['total_days']}")
        else:
            print("[WARN] Field 'total_days' MISSING! (Frontend might break)")
            print(f"Keys: {target_book.keys()}")
    else:
        print("[FAIL] Target book not found in available list.")
        return

    # 3. Test 'Subscribe' API
    url_subscribe = f'/vocab/api/v1/books/{book1.id}/subscribe/'
    print(f"Subscribing to book {book1.id}...")
    
    response = client.post(url_subscribe)
    
    if response.status_code != 200:
        print(f"[FAIL] Subscribe Failed: {response.status_code} {response.data}")
        return
        
    print("[OK] Subscribe API successful.")

    # 4. Verify 'Available' API again (Should NOT contain the subscribed book)
    print("Checking available books again...")
    response = client.get(url_available)
    data = response.data
    
    target_book_after = next((b for b in data if b['id'] == book1.id), None)
    
    if target_book_after is None:
        print("[OK] Book correctly removed from 'Available' list after subscription.")
    else:
        print("[FAIL] Book STILL presents in 'Available' list after subscription.")

    print("--- Verification Complete ---")

if __name__ == '__main__':
    run_verification()
