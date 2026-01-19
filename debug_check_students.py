
import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from core.models import StudentProfile, Branch

def check_students():
    print(f"Total students: {StudentProfile.objects.count()}")
    
    anyang = Branch.objects.filter(name='안양').first()
    dongtan = Branch.objects.filter(name='동탄').first()
    
    if anyang:
        count = StudentProfile.objects.filter(branch=anyang).count()
        print(f"Anyang students: {count}")
        # Print first 5 Anyang students to check who they are
        for s in StudentProfile.objects.filter(branch=anyang)[:5]:
            print(f" - {s.name} ({s.phone_number})")
    else:
        print("Anyang branch not found")

    if dongtan:
        count = StudentProfile.objects.filter(branch=dongtan).count()
        print(f"Dongtan students: {count}")
    else:
        print("Dongtan branch not found")

if __name__ == "__main__":
    check_students()
