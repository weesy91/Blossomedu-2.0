from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import permissions
from django.utils import timezone
from datetime import timedelta
from ..models import AssignmentTask, Attendance, ClassLog, TemporarySchedule
from core.models import StudentProfile
from django.db.models import Q

class TeacherDashboardView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        now = timezone.now()
        today = now.date()

        # 1. My Students
        # Filter students where current user is the teacher for ANY subject
        # Also ensure student is active
        my_students = StudentProfile.objects.filter(
            Q(syntax_teacher=user) | 
            Q(reading_teacher=user) | 
            Q(extra_class_teacher=user),
            is_active=True
        ).distinct()

        # 2. Overdue Assignments
        # Uncompleted, Due date passed
        # Exclude those rejected? No, rejected means they need to redo it, so it's still "action required" or "pending".
        # But 'overdue' specifically means due_date < now and is_completed=False.
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

        # 3. Missing Class Logs (Last 14 days)
        missing_logs = []
        check_start_date = today - timedelta(days=14)
        
        # Get recent attendances (PRESENT/LATE) for my students
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

            # We DO NOT handle TemporarySchedule overrides completely here for simplicity.
            # (e.g. if class was moved FROM today to another day, we might falsely flag missing log)
            # But "Attendance" is PRESENT, meaning they CAME. So a log SHOULD be written for whatever they did.
            # If they came for a make-up, the Log subject might be different, but if they came for regular class, we expect regular log.
            
            for subj in subjects_today:
                exists = ClassLog.objects.filter(
                    student=student,
                    date=att.date,
                    subject=subj
                ).exists()
                
                if not exists:
                    # Double check if there is ANY log for this student on this day by this teacher?
                    # Sometimes teacher selects wrong subject.
                    # But strict check helps compliance.
                    missing_logs.append({
                        'type': 'MISSING_LOG',
                        'student_id': student.id,
                        'student_name': student.name,
                        'date': att.date.isoformat(),
                        'subject': subj,
                        'label': f"{student.name} - {subj} (일지 미작성)"
                    })

        # 4. Unscheduled Absences (Last 30 days)
        unscheduled_absences = []
        absent_check_start = today - timedelta(days=30)
        recent_absent = Attendance.objects.filter(
            student__in=my_students,
            date__gte=absent_check_start,
            date__lte=today,
            status='ABSENT'
        ).select_related('student')

        for att in recent_absent:
            # Check if covered by Temp Schedule
            has_makeup = TemporarySchedule.objects.filter(
                student=att.student,
                original_date=att.date
            ).exists()
            
            if not has_makeup:
                unscheduled_absences.append({
                    'type': 'NO_MAKEUP',
                    'student_id': att.student.id,
                    'student_name': att.student.name,
                    'date': att.date.isoformat(),
                    'label': f"{att.student.name} - 결석 (보강 미잡힘)"
                })

        return Response({
            'overdue_assignments': overdue_data,
            'action_required': missing_logs + unscheduled_absences
        })