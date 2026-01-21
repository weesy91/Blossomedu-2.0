from django.core.management.base import BaseCommand
from academy.models import ClassLog
from core.models.users import StudentProfile
from django.utils import timezone
from datetime import datetime, timedelta

class Command(BaseCommand):
    help = 'Fixes ClassLogs that are marked as SYNTAX but occurred on a READING day (and vice versa) based on student schedule.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--dry-run',
            action='store_true',
            help='Simulate the fix without modifying the database.',
        )

    def handle(self, *args, **options):
        dry_run = options['dry_run']
        # Target: Recent logs (e.g., from Jan 1 2026)
        start_date = datetime(2026, 1, 1).date()
        logs = ClassLog.objects.filter(date__gte=start_date)
        
        count = logs.count()
        mode_str = "[DRY RUN] " if dry_run else ""
        self.stdout.write(f"{mode_str}Checking {count} logs since {start_date}...")

        updated_count = 0
        
        # Day mapping: Python strftime('%a') -> ClassTime.day (assumed 3-char code like 'Mon' or full string?)
        # Let's inspect ClassTime later or assume 'Mon', 'Tue' based on previous context.
        # Front-end code handled 'Mon' -> '월요일'.
        # Assuming DB stores 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'.
        
        for log in logs:
            student = log.student
            if not student:
                continue

            log_date = log.date
            # English short day: Mon, Tue, Wed...
            day_code = log_date.strftime('%a') 
            
            # 1. Get Scheduled Classes
            syntax_day = None
            reading_day = None
            
            if student.syntax_class:
                syntax_day = student.syntax_class.day 
            
            if student.reading_class:
                reading_day = student.reading_class.day

            # 2. Heuristic Logic
            # Case A: Log is SYNTAX, but Day matches READING (and NOT Syntax)
            if log.subject == 'SYNTAX':
                if reading_day == day_code and syntax_day != day_code:
                    self.stdout.write(f"{mode_str}[FIX] {student.name} {log_date} ({day_code}): SYNTAX -> READING")
                    if not dry_run:
                        log.subject = 'READING'
                        log.save()
                    updated_count += 1
            
            # Case B: Log is READING, but Day matches SYNTAX (and NOT Reading)
            elif log.subject == 'READING':
                if syntax_day == day_code and reading_day != day_code:
                    self.stdout.write(f"{mode_str}[FIX] {student.name} {log_date} ({day_code}): READING -> SYNTAX")
                    if not dry_run:
                        log.subject = 'SYNTAX'
                        log.save()
                    updated_count += 1
            
        if dry_run:
             self.stdout.write(self.style.SUCCESS(f"[DRY RUN] Would fix {updated_count} logs."))
        else:
             self.stdout.write(self.style.SUCCESS(f"Successfully fixed {updated_count} logs."))
