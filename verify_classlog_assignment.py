
import os
import django
from datetime import timedelta
from django.utils import timezone

# Setup Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.contrib.auth import get_user_model
from core.models import StudentProfile
from academy.models import ClassLog, AssignmentTask, Textbook
from vocab.models import WordBook, Publisher

User = get_user_model()

def run_verification():
    print("=== Verifying ClassLog -> Assignment Auto-Creation Logic ===")

    # 1. Setup Data
    # Create Teacher
    teacher_user, _ = User.objects.get_or_create(username='test_teacher_assign')
    # Use StaffProfile to mark as teacher (if needed by signals, though ClassLog only needs a User instance for 'teacher' field)
    # Checking models.py, ClassLog.teacher is ForeignKey to AUTH_USER_MODEL.
    
    # Create Student
    student_user, _ = User.objects.get_or_create(username='test_student_assign')
    student, _ = StudentProfile.objects.get_or_create(user=student_user, defaults={'name': 'Assign Student'})

    # Create WordBook
    pub, _ = Publisher.objects.get_or_create(name='Test Pub')
    wordbook, _ = WordBook.objects.get_or_create(title='Verify Vocab Book', defaults={'publisher': pub, 'uploaded_by': teacher_user})
    
    # Create Textbook
    textbook, _ = Textbook.objects.get_or_create(title='Verify Textbook', defaults={'category': 'SYNTAX'})

    print(f"Student: {student.name}, Teacher: {teacher_user.username}")

    # 2. Test Case 1: Manual Assignment (Textbook)
    print("\n[Test 1] Creating ClassLog with Textbook Homework...")
    today = timezone.now().date()
    due_date = today + timedelta(days=7)

    log1 = ClassLog.objects.create(
        student=student,
        teacher=teacher_user,
        date=today,
        subject='SYNTAX',
        hw_main_book=textbook,
        hw_main_range='p.10 ~ p.20',
        hw_due_date=due_date
    )

    # Check Assignments
    tasks = AssignmentTask.objects.filter(origin_log=log1)
    print(f"-> Created {tasks.count()} tasks for Log 1")
    
    manual_task = tasks.filter(assignment_type='MANUAL').first()
    if manual_task:
        print(f"   [PASS] Manual Task Created: {manual_task.title} (Due: {manual_task.due_date})")
        if manual_task.title == f"[{textbook.title}] p.10 ~ p.20 풀기":
             print("   [PASS] Title matches expected format")
        else:
             print(f"   [FAIL] Title mismatch: {manual_task.title}")
    else:
        print("   [FAIL] No Manual Task created")

    # 3. Test Case 2: Vocab Assignment N-Split
    # Range 1-10 (10 days), Due Date 5 days later -> Should consist of ~2 days per chunk or similar logic
    print("\n[Test 2] Creating ClassLog with Vocab Homework (N-Split)...")
    
    vocab_due_date = today + timedelta(days=5) # 5 days to do it
    # Range 1-10 means 10 chapters. 5 days. Expect 2 chapters/day.
    
    log2 = ClassLog.objects.create(
        student=student,
        teacher=teacher_user,
        date=today,
        subject='SYNTAX',
        hw_vocab_book=wordbook,
        hw_vocab_range='1-10', # Trigger N-Split
        hw_due_date=vocab_due_date
    )
    
    vocab_tasks = AssignmentTask.objects.filter(origin_log=log2, assignment_type='VOCAB_TEST')
    count = vocab_tasks.count()
    print(f"-> Created {count} Vocab tasks for Log 2 (Expected around 5 for N-Split)")
    
    if count > 1:
        print(f"   [PASS] N-Split triggered. Created {count} tasks.")
        for t in vocab_tasks.order_by('due_date'):
            print(f"     - {t.title} (Due: {t.due_date}) [Range: {t.vocab_range_start}~{t.vocab_range_end}]")
            
        # Verify coverage
        min_start = vocab_tasks.order_by('vocab_range_start').first().vocab_range_start
        max_end = vocab_tasks.order_by('-vocab_range_end').first().vocab_range_end
        if min_start == 1 and max_end == 10:
             print("   [PASS] Range 1-10 fully covered.")
        else:
             print(f"   [FAIL] Range coverage incomplete: {min_start}~{max_end}")

    else:
        print("   [FAIL] N-Split NOT triggered (Only 1 task created). Check Regex or Logic.")
        if count == 1:
            print(f"     - Task: {vocab_tasks.first().title}")

    # Cleanup
    print("\nCleaning up test data...")
    log1.delete()
    log2.delete()
    # Student/Teacher kept for other tests or manual cleanup

if __name__ == '__main__':
    run_verification()
