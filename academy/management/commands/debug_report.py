from django.core.management.base import BaseCommand
from academy.models import ClassLog, Student
from vocab.models import TestResult
from django.db.models import Count

class Command(BaseCommand):
    help = 'Debug Report Data'

    def handle(self, *args, **options):
        # 1. Find the student (Blossomedu동탄_02 context)
        # Assuming last student or specific one. Let's list a few.
        students = Student.objects.all()[:5]
        print(f"Found {students.count()} students.")

        target_student = None
        for s in students:
            print(f"Checking student: {s.name} ({s.username})")
            # Check for logs
            logs = ClassLog.objects.filter(student=s)
            if logs.exists():
                target_student = s
                break
        
        if not target_student:
             print("No student with logs found.")
             return

        print(f"--- Debugging Student: {target_student.name} ---")
        
        # 2. Check ClassLogs
        logs = ClassLog.objects.filter(student=target_student).order_by('-date')
        print(f"Total Logs: {logs.count()}")
        
        for l in logs[:5]:
            print(f"  Log {l.date}: Entries={l.entries.count()}")
            for e in l.entries.all():
                print(f"    - Entry: TB={e.textbook}, WB={e.wordbook}, Range={e.progress_range}, Score={e.score}")

        # 3. Check TestResults
        tests = TestResult.objects.filter(student_id=target_student.id)
        print(f"Total TestResults: {tests.count()}")
        for t in tests[:5]:
            print(f"  Test {t.created_at}: Book={t.book}, Range={t.test_range}, Score={t.score}")
