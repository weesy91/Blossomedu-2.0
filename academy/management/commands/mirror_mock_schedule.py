from django.core.management.base import BaseCommand
from core.models import ClassTime

class Command(BaseCommand):
    help = 'Mirrors READING schedules to create MOCK schedules'

    def handle(self, *args, **options):
        # 1. Find all READING schedules
        readings = ClassTime.objects.filter(class_type='READING')
        self.stdout.write(f"Found {readings.count()} READING schedules.")

        created_count = 0
        for r in readings:
            # 2. Check if a duplicate MOCK schedule already exists (idempotency)
            # We match key fields: branch, day, start_time
            exists = ClassTime.objects.filter(
                branch=r.branch,
                day=r.day,
                start_time=r.start_time,
                class_type='MOCK'
            ).exists()

            if not exists:
                # 3. Create MOCK schedule
                # [FIX] Standardize name: "모의고사 HH:MM"
                # (Ignore original name to avoid "Fri 16:00" vs "16:00" inconsistency)
                time_str = r.start_time.strftime('%H:%M')
                new_name = f"모의고사 {time_str}"

                ClassTime.objects.create(
                    branch=r.branch,
                    name=new_name,
                    day=r.day,
                    start_time=r.start_time,
                    end_time=r.end_time,
                    class_type='MOCK'
                )
                created_count += 1
                self.stdout.write(f"Created: {new_name} ({r.day} {r.start_time})")
        
        self.stdout.write(self.style.SUCCESS(f"Successfully created {created_count} MOCK schedules."))
