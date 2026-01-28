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
                # Replace '독해' or 'Reading' in name with '모의고사'
                new_name = r.name.replace('독해', '모의고사').replace('Reading', 'Mock')
                if '모의고사' not in new_name and 'Mock' not in new_name:
                    new_name = f"{new_name} (모의고사)"

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
