
import os
import django
from django.conf import settings

# Setup Django Environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth.models import User
from core.models import StudentProfile, StaffProfile, Branch
from rest_framework.test import APIClient
from rest_framework import status

def run_verification():
    print("--- Starting Account Lifecycle Verification ---")

    # 1. Setup Admin/Teacher User for API calls
    admin_user, created = User.objects.get_or_create(username='test_admin')
    if created:
        admin_user.set_password('password123')
        admin_user.is_staff = True
        admin_user.save()
        # Ensure StaffProfile exists
        StaffProfile.objects.create(user=admin_user, name="Admin Teacher")
    
    client = APIClient()
    client.force_authenticate(user=admin_user)
    print("[OK] Authenticated as Admin")

    # 2. Register a New Student via API
    # Using the Registration ViewSet to ensure full flow coverage
    reg_url = '/core/api/v1/registration/student/create_student/'
    student_data = {
        'username': 'lifecycle_test_student',
        'password': 'password123',
        'name': 'Lifecycle Monitor',
        'phone_number': '010-1111-2222',
        'grade': 8,
    }

    # Cleanup previous run
    if User.objects.filter(username='lifecycle_test_student').exists():
        print("[INFO] Cleaning up existing test user...")
        User.objects.get(username='lifecycle_test_student').delete()

    print(f"Creating student via {reg_url}...")
    response = client.post(reg_url, student_data, format='json')
    
    if response.status_code != 201:
        print(f"[FAIL] Registration Failed: {response.status_code} {response.data}")
        return
    
    student_id = response.data['student_id']
    print(f"[OK] Student Created. ID: {student_id}")

    # 3. Verify Initial Active State
    student_profile = StudentProfile.objects.get(id=student_id)
    if student_profile.user.is_active:
        print("[OK] Student is ACTIVE by default.")
    else:
        print("[FAIL] Student created as INACTIVE.")
        return

    # 4. Test Deactivation (PATCH)
    mgmt_url = f'/core/api/v1/management/students/{student_id}/'
    print(f"Deactivating student via {mgmt_url}...")
    
    # Payload for deactivation
    # Note: Serializer expects 'is_active' field which maps to user.is_active
    patch_data = {'is_active': False}
    
    response = client.patch(mgmt_url, patch_data, format='json')
    
    if response.status_code != 200:
        print(f"[FAIL] Update Failed: {response.status_code} {response.data}")
        return

    student_profile.refresh_from_db()
    if not student_profile.user.is_active:
        print("[OK] Student Deactivated successfully.")
    else:
        print("[FAIL] Student IS STILL ACTIVE after patch.")
        # Debugging: maybe serializer logic is wrong
        print(f"Debug: Response Data: {response.data}")
        return

    # 5. Test Reactivation
    print("Reactivating student...")
    patch_data = {'is_active': True}
    response = client.patch(mgmt_url, patch_data, format='json')
    
    student_profile.refresh_from_db()
    if student_profile.user.is_active:
        print("[OK] Student Reactivated successfully.")
    else:
        print("[FAIL] Student Reactivation Failed.")
        return

    # 6. Test Deletion
    print("Deleting student...")
    response = client.delete(mgmt_url)
    
    if response.status_code == 204:
        print("[OK] Delete API returned 204.")
    else:
        print(f"[FAIL] Delete API returned {response.status_code}.")
        return

    # Verify Database
    if not StudentProfile.objects.filter(id=student_id).exists():
        print("[OK] StudentProfile removed from DB.")
    else:
        print("[FAIL] StudentProfile STILL EXISTS in DB.")

    if not User.objects.filter(username='lifecycle_test_student').exists():
        print("[OK] User removed from DB.")
    else:
        print("[FAIL] User STILL EXISTS in DB.")

    print("--- Verification Complete ---")

if __name__ == '__main__':
    run_verification()
