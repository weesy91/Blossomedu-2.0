
from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from core.models import StudentProfile

class Command(BaseCommand):
    help = 'Delete all students to reset data'

    def handle(self, *args, **options):
        # Delete all student profiles
        count = StudentProfile.objects.count()
        StudentProfile.objects.all().delete()
        self.stdout.write(self.style.SUCCESS(f'Successfully deleted {count} student profiles.'))
        
        # Cleanup users who were students (optional, but good for clean reset)
        # Assuming student users have phone number as username (all digits)
        # Or we can just leave them, but they might conflict if we re-create them.
        # Ideally, import_students uses get_or_create, so leaving Users is fine, 
        # but if we want a clean slate, maybe delete orphan users?
        # For now, let's validly only delete profiles to be safe, 
        # or deleting users that match the student pattern.
        
        # Let's just delete the profiles as requested. The imports will reuse existing users if they exist.
