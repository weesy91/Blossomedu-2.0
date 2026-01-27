from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import timedelta
from django.db.models import Q
from core.models import StudentProfile, StaffProfile
from academy.models import Attendance, TemporarySchedule, ClassLog, AssignmentTask
from django.contrib.auth import get_user_model

class Command(BaseCommand):
    def handle(self, *args, **options):
        User = get_user_model()
        # Find the teacher
        try:
            profile = StaffProfile.objects.get(name="위승연")
            user = profile.user
            print(f"Found user: {user.username} (Staff: {profile.name})")
        except StaffProfile.DoesNotExist:
            print("Teacher '위승연' not found via StaffProfile. Trying User name...")
            try:
                user = User.objects.get(name="위승연")
            except:
                print("User not found.")
                return

        now = timezone.now()
        today = now.date()

        print("--- 1. My Students ---")
        my_students = StudentProfile.objects.filter(
            Q(syntax_teacher=user) | 
            Q(reading_teacher=user) | 
            Q(extra_class_teacher=user),
            is_active=True
        ).distinct()
        print(f"Count: {my_students.count()}")

        print("--- 2. Overdue Assignments ---")
        try:
            overdue_qs = AssignmentTask.objects.filter(
                student__in=my_students,
                is_completed=False,
                due_date__lt=now
            ).select_related('student').order_by('due_date')[:20] 

            overdue_data = []
            for a in overdue_qs:
                overdue_data.append({
                    'id': a.id,
                    'student_name': a.student.name,
                    'title': a.title,
                    'due_date': a.due_date.isoformat(),
                    'days_overdue': (now - a.due_date).days
                })
            print(f"Overdue Processed: {len(overdue_data)}")
        except Exception as e:
            print(f"ERROR in Overdue: {e}")
            import traceback
            traceback.print_exc()

        print("--- 3. Missing Class Logs ---")
        try:
            missing_logs = []
            check_start_date = today - timedelta(days=14)
            
            recent_att = Attendance.objects.filter(
                student__in=my_students,
                date__gte=check_start_date,
                date__lte=today, 
                status__in=['PRESENT', 'LATE']
            ).select_related('student', 'student__syntax_class', 'student__reading_class', 'student__extra_class')

            weekday_map = {0:'Mon', 1:'Tue', 2:'Wed', 3:'Thu', 4:'Fri', 5:'Sat', 6:'Sun'}
            
            for att in recent_att:
                day_str = weekday_map[att.date.weekday()]
                student = att.student
                subjects_today = []
                
                # Check Regular Schedule matching this teacher
                if student.syntax_class and student.syntax_class.day == day_str and student.syntax_teacher == user:
                    subjects_today.append('SYNTAX')
                if student.reading_class and student.reading_class.day == day_str and student.reading_teacher == user:
                    subjects_today.append('READING')
                # Extra/Grammar
                if student.extra_class and student.extra_class.day == day_str and student.extra_class_teacher == user:
                    subjects_today.append('GRAMMAR')
                
                for subj in subjects_today:
                    exists = ClassLog.objects.filter(
                        student=student,
                        date=att.date,
                        subject=subj
                    ).exists()
                    
                    if not exists:
                        missing_logs.append({
                            'type': 'MISSING_LOG',
                            'student_id': student.id,
                            'student_name': student.name,
                            'date': att.date.isoformat(),
                            'subject': subj
                        })
            print(f"Missing Logs Processed: {len(missing_logs)}")
        except Exception as e:
            print(f"ERROR in Missing Logs: {e}")
            import traceback
            traceback.print_exc()

        print("--- 4. Unscheduled Absences ---")
        try:
            unscheduled_absences = []
            absent_check_start = today - timedelta(days=30)
            recent_absent = Attendance.objects.filter(
                student__in=my_students,
                date__gte=absent_check_start,
                date__lte=today,
                status='ABSENT'
            ).select_related('student')

            for att in recent_absent:
                has_makeup = TemporarySchedule.objects.filter(
                    student=att.student,
                    original_date=att.date
                ).exists()
                
                if not has_makeup:
                    unscheduled_absences.append({
                        'type': 'NO_MAKEUP',
                        'student_id': att.student.id,
                        'student_name': att.student.name,
                        'date': att.date.isoformat()
                    })
            print(f"Absences Processed: {len(unscheduled_absences)}")
        except Exception as e:
            print(f"ERROR in Absences: {e}")
            import traceback
            traceback.print_exc()
