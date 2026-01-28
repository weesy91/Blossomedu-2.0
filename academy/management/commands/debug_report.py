from django.core.management.base import BaseCommand
from academy.models import ClassLog, StudentReport
from core.models import StudentProfile
from django.utils import timezone
import datetime

class Command(BaseCommand):
    help = 'Debug Report Data Integrity'

    def handle(self, *args, **options):
        print("--- START DEBUG ---")
        try:
            # 1. Get first student with logs
            student = None
            for s in StudentProfile.objects.all():
                if ClassLog.objects.filter(student=s).exists():
                    student = s
                    break
            
            if not student:
                print("No student with logs found.")
                return

            print(f"Target Student: {student.name} (ID: {student.id})")

            # 2. Simulate Report Query (Section 4)
            # Use a wide range
            start = datetime.date(2025, 1, 1)
            end = datetime.date(2026, 12, 31)
            
            print(f"Querying Logs between {start} and {end}...")
            
            logs_qs = ClassLog.objects.filter(
                student_id=student.id,
                date__range=[start, end]
            ).prefetch_related('entries').order_by('-date')
            
            count = logs_qs.count()
            print(f"Found {count} logs.")
            
            if count > 0:
                l = logs_qs.first()
                print(f"First Log: {l.date}, Subject: {l.subject}")
                print(f"Entries: {l.entries.count()}")
                for e in l.entries.all():
                    print(f"  - {e}")
                    
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"ERROR: {e}")
        print("--- END DEBUG ---")
