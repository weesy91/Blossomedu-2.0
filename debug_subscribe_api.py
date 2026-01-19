import os
import django
import sys

sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from rest_framework.test import APIClient
from django.contrib.auth import get_user_model
from vocab.models import WordBook

User = get_user_model()

def test_subscribe():
    print("=== Testing Subscribe API ===")
    
    # 1. Login
    try:
        user = User.objects.get(username='test_student')
        client = APIClient()
        client.force_authenticate(user=user)
        print(f"Logged in as {user.username}")
    except Exception as e:
        print(f"Login failed: {e}")
        return

    # 2. Get Available Books
    print("\n--- Available Books ---")
    response = client.get('/vocab/api/v1/books/available/')
    if response.status_code != 200:
        print(f"Failed to get available books: {response.status_code}")
        print(response.content)
        return

    books = response.data
    if not books:
        print("No available books found.")
        return
        
    for b in books:
        print(f"[{b['id']}] {b['title']}")
        
    target_book = books[0]
    target_id = target_book['id']
    
    # 3. Try to Subscribe
    print(f"\n--- Subscribing to Book {target_id} ---")
    url = f'/vocab/api/v1/books/{target_id}/subscribe/'
    print(f"POST {url}")
    
    response = client.post(url)
    print(f"Status: {response.status_code}")
    print(f"Response: {response.data}")
    
    if response.status_code == 404:
        print("!!! 404 ERROR !!!")
        print("Possible causes: URL mismatch, ID calculation error, or method missing.")

if __name__ == '__main__':
    test_subscribe()
