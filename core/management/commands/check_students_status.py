
from django.core.management.base import BaseCommand
from core.models import StudentProfile, Branch

class Command(BaseCommand):
    help = 'Check student status'

    def handle(self, *args, **options):
        self.stdout.write(f"Total students: {StudentProfile.objects.count()}")
        
        anyang = Branch.objects.filter(name='안양').first()
        dongtan = Branch.objects.filter(name='동탄').first()
        
        if anyang:
            count = StudentProfile.objects.filter(branch=anyang).count()
            self.stdout.write(f"Anyang students: {count}")
            for s in StudentProfile.objects.filter(branch=anyang)[:5]:
                self.stdout.write(f" - {s.name} ({s.phone_number})")
        else:
            self.stdout.write("Anyang branch not found")

        if dongtan:
            count = StudentProfile.objects.filter(branch=dongtan).count()
            self.stdout.write(f"Dongtan students: {count}")
        else:
            self.stdout.write("Dongtan branch not found")
