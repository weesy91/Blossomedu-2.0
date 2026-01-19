import os
import django
from django.utils import timezone
from datetime import timedelta

# Setup Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from core.models import StudentProfile
from academy.models import AssignmentTask, ClassLog
from vocab.models import WordBook, Word, Publisher, TestResult
from vocab import views_api
from rest_framework.test import APIRequestFactory

User = get_user_model()

def run_verification():
    print("=== Verifying Assignment Completion Logic ===")

    # 1. Setup Data
    student_user, _ = User.objects.get_or_create(username='test_student_complete')
    student_profile, _ = StudentProfile.objects.get_or_create(user=student_user, defaults={'name': 'Complete Student'})
    
    pub, _ = Publisher.objects.get_or_create(name='Test Pub')
    wordbook, _ = WordBook.objects.get_or_create(title='Complete Book', defaults={'publisher': pub, 'uploaded_by': student_user})
    
    # Create Words
    for i in range(1, 4):
        Word.objects.get_or_create(book=wordbook, english=f'word{i}', defaults={'korean': '뜻', 'number': 1})

    # Create Manual ClassLog & Assignment
    # We need a VOCAB_TEST assignment
    log = ClassLog.objects.create(
        student=student_profile,
        teacher=student_user, # Self-taught for test
        date=timezone.now().date(),
        subject='SYNTAX',
    )
    
    task = AssignmentTask.objects.create(
        student=student_profile,
        origin_log=log,
        title='Vocab Task 1',
        assignment_type='VOCAB_TEST',
        due_date=timezone.now().date(),
        related_vocab_book=wordbook,
        vocab_range_start=1,
        vocab_range_end=1
    )
    
    print(f"Created Task: {task.id} (Completed: {task.is_completed})")

    # 2. Simulate Submit Request
    factory = APIRequestFactory()
    view = views_api.TestViewSet.as_view({'post': 'submit'})
    
    # Payload
    data = {
        'book_id': wordbook.id,
        'assignment_id': task.id,
        'range': '1',
        'details': [
            {'english': 'word1', 'user_input': '뜻'},
            {'english': 'word2', 'user_input': '뜻'},
            {'english': 'word3', 'user_input': '뜻'},
        ],
        'mode': 'challenge'
    }
    
    print("Simulating Submit...")
    request = factory.post('/vocab/api/v1/tests/submit/', data, format='json')
    request.user = student_user
    
    response = view(request)
    
    print(f"Response Status: {response.status_code}")
    print(f"Response Data: {response.data}")
    
    # 3. Verify Task Completion
    task.refresh_from_db()
    if task.is_completed:
        print("[PASS] Assignment marked as COMPLETED!")
    else:
        print("[FAIL] Assignment NOT completed (Score check or Logic error?)")

    # 4. cleanup
    task.delete()
    log.delete()
    # wordbook etc left

if __name__ == '__main__':
    run_verification()
