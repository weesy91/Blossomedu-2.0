
import os
import sys

print("--- Script Starting ---")

try:
    import django
    import json
    import datetime
    from django.core.serializers.json import DjangoJSONEncoder
    from django.core.exceptions import ObjectDoesNotExist
    
    # Setup Django
    os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
    print("Setting up Django...")
    django.setup()
    print("Django Setup Complete")
except Exception as e:
    print(f"Startup Error: {e}")
    sys.exit(1)

try:
    from core.models import StudentProfile
    from academy.models import Attendance, ClassLog, AssignmentTask
    from vocab.models import TestResult
    from django.db.models import Prefetch
    print("Models Imported")
except Exception as e:
    print(f"Import Error: {e}")
    sys.exit(1)

def recursive_serialize(data):
    if data is None: 
        return None
    if isinstance(data, dict):
        return {k: recursive_serialize(v) for k, v in data.items()}
    elif isinstance(data, list):
        return [recursive_serialize(item) for item in data]
    elif hasattr(data, 'isoformat'):
        return data.isoformat()
    elif hasattr(data, 'url'): # Handle ImageFieldFile
        try:
            return data.url
        except ValueError:
            return None
    return data

def aggregate_data(student_id, start, end):
    # (Copied logic from report.py)
    attendances = Attendance.objects.filter(
        student_id=student_id, 
        date__range=[start, end]
    ).values('date', 'status', 'check_in_time')
    
    vocab_qs = TestResult.objects.filter(
        student_id=student_id,
        created_at__date__range=[start, end]
    ).select_related('book').prefetch_related('details').order_by('created_at')
    
    vocab_tests = []
    cumulative_passed = 0
    
    for v in vocab_qs:
        wrong_words = []
        for d in v.details.all():
            if not d.is_correct:
                wrong_words.append({
                    'word': d.word_question,
                    'student': d.student_answer,
                    'answer': d.correct_answer
                })
        
        cumulative_passed += v.score
        
        vocab_tests.append({
            'created_at': v.created_at,
            'score': v.score,
            'total_count': v.total_count,
            'wrong_count': v.wrong_count,
            'book__title': v.book.title,
            'test_range': v.test_range,
            'wrong_words': wrong_words,
            'cumulative_passed': cumulative_passed, 
        })

    assignments_qs = AssignmentTask.objects.filter(
        student_id=student_id,
        due_date__date__range=[start, end]
    ).select_related('related_textbook', 'related_vocab_book').prefetch_related('submission').order_by('due_date')
    
    assignments = []
    for a in assignments_qs:
        feedback = ''
        status = '미제출'
        submission_image = None
        
        try:
            submission = a.submission
            feedback = submission.teacher_comment
            status = submission.get_status_display()
            if submission.image and submission.image.name:
                submission_image = submission.image.url
        except ObjectDoesNotExist:
            if a.is_completed:
                status = '완료'
        
        assignments.append({
            'title': a.title,
            'due_date': a.due_date,
            'is_completed': a.is_completed,
            'assignment_type': a.get_assignment_type_display(),
            'status': status,
            'feedback': feedback,
            'submission_image': submission_image,
        })

    logs_qs = ClassLog.objects.filter(
        student_id=student_id,
        date__range=[start, end]
    ).prefetch_related('entries', 'entries__textbook', 'entries__wordbook', 'generated_assignments').order_by('-date')
    
    logs = []
    for l in logs_qs:
        details = []
        for e in l.entries.all():
            book_name = e.textbook.title if e.textbook else (e.wordbook.title if e.wordbook else '기타')
            score_str = e.score or '-'
            details.append({
                'text': f"{book_name} ({e.progress_range})",
                'score': score_str,
            })
        
        homeworks = []
        for t in l.generated_assignments.all():
            homeworks.append({
                'title': t.title,
                'due_date': t.due_date,
                'is_completed': t.is_completed,
            })
        
        logs.append({
            'date': l.date,
            'subject': l.get_subject_display(),
            'subject_code': l.subject, 
            'comment': l.comment,
            'teacher_comment': l.teacher_comment,
            'details': details,
            'homeworks': homeworks,
        })
    
    total_days = len(attendances)
    present_days = sum(1 for a in attendances if a['status'] == 'PRESENT')
    vocab_avg = 0
    if vocab_tests:
        vocab_avg = sum(t['score'] for t in vocab_tests) / len(vocab_tests)

    return {
        'stats': {
            'attendance_rate': (present_days / total_days * 100) if total_days > 0 else 0,
            'vocab_avg': round(vocab_avg, 1),
            'assignment_count': len(assignments),
            'assignment_completed': sum(1 for a in assignments if a['is_completed']),
            'total_passed_words': cumulative_passed, 
        },
        'attendance': recursive_serialize(list(attendances)),
        'vocab': recursive_serialize(vocab_tests),
        'assignments': recursive_serialize(assignments),
        'logs': recursive_serialize(logs),
    }

def debug():
    student = StudentProfile.objects.first()
    if not student:
        print("No student found!")
        return
    
    print(f"Using Student: {student.name} ({student.id})")
    data = aggregate_data(student.id, '2024-01-01', '2025-12-31')
    
    print("Trying to serialize...")
    try:
        json_output = json.dumps(data, cls=DjangoJSONEncoder)
        print("SUCCESS! JSON length:", len(json_output))
    except TypeError as e:
        print("Use a custom encoder to find the culprit...")
        class DebugEncoder(json.JSONEncoder):
            def default(self, obj):
                try:
                    return super().default(obj)
                except TypeError:
                    print(f"!!! UNSERIALIZABLE OBJECT FOUND: {type(obj)} -> {obj}")
                    return str(obj)
        
        json.dumps(data, cls=DebugEncoder)

if __name__ == "__main__":
    debug()
