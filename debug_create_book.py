import os
import django
import sys

# Setup Django environment
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from academy.models import Textbook, TextbookUnit
from rest_framework.test import APIRequestFactory, force_authenticate
from academy.views_api import TextbookViewSet

User = get_user_model()

def test_create_textbook():
    print("Running Textbook API Test...")
    
    # Get Admin or Staff User
    user = User.objects.filter(is_staff=True).first()
    if not user:
        print("No staff user found. Creating one.")
        user = User.objects.create_superuser('admin_test', 'admin@test.com', 'password123')

    factory = APIRequestFactory()
    view = TextbookViewSet.as_view({'post': 'create', 'get': 'list'})

    # 1. Create Data
    data = {
        'title': 'Test Syntax Book',
        'publisher': 'Test Pub',
        'level': 'High 1',
        'category': 'SYNTAX',
        'total_units': 2,
        'units': [
            {'unit_number': 1, 'link_url': 'http://example.com/1'},
            {'unit_number': 2, 'link_url': 'http://example.com/2'}
        ]
    }

    request = factory.post('/academy/api/v1/textbooks/', data, format='json')
    force_authenticate(request, user=user)
    response = view(request)
    
    print(f"Create Response: {response.status_code}")
    if response.status_code == 201:
        print("Create Success:", response.data)
        created_id = response.data['id']
        # Check units in response or query DB
        if len(response.data.get('units', [])) != 2:
             print("WARNING: Units not in response properly:", response.data.get('units'))
        
        # [NEW] Test Update total_units
        print("Testing Update total_units to 20")
        update_data = {
            'total_units': 20,
            # Validation might require title etc if not partial
        }
        # Assuming partial update (PATCH)? ViewSet supports partial_update by default.
        request_update = factory.patch(f'/academy/api/v1/textbooks/{created_id}/', update_data, format='json')
        force_authenticate(request_update, user=user)
        # Using partial_update method of ViewSet
        view_detail = TextbookViewSet.as_view({'patch': 'partial_update'})
        response_update = view_detail(request_update, pk=created_id)
        
        print(f"Update Response: {response_update.status_code}")
        if response_update.status_code == 200:
             print("Update Data:", response_update.data)
             if response_update.data['total_units'] == 20:
                 print("PASS: total_units updated.")
             else:
                 print("FAIL: total_units mismatch")
        else:
             print("Update Failed")

    else:
        print("Create Failed:", response.data)
        return

    # 2. List Data
    request_list = factory.get('/academy/api/v1/textbooks/?category=SYNTAX')
    force_authenticate(request_list, user=user)
    response_list = view(request_list)
    print(f"List Response: {response_list.status_code}")
    # print("List Data:", response_list.data)
    
    found = False
    for book in response_list.data:
        if book['title'] == 'Test Syntax Book':
            found = True
            print(f"Found Book ID {book['id']}. Units Count: {len(book['units'])}")
            if len(book['units']) != 2:
                print("FAIL: Units count mismatch in List")
            else:
                print("PASS: Units verified.")

    if not found:
        print("FAIL: Book not found in list")

    # 3. Clean up
    if response.status_code == 201:
        created_id = response.data['id']
        Textbook.objects.get(id=created_id).delete()
        print("Cleaned up.")

if __name__ == '__main__':
    test_create_textbook()
