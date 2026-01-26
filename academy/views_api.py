from rest_framework import viewsets, permissions, status
from rest_framework.exceptions import PermissionDenied
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import AssignmentTask, AssignmentSubmission, AssignmentSubmissionImage, Attendance, ClassLog, TemporarySchedule, Textbook
from .serializers import AssignmentTaskSerializer, AssignmentSubmissionSerializer, AttendanceSerializer, TextbookSerializer
from core.models import StudentProfile # [NEW]
from django.utils import timezone
from datetime import date, datetime, time as dt_time

class AssignmentViewSet(viewsets.ModelViewSet):
    """
    과제 관리 API
    """
    queryset = AssignmentTask.objects.all()
    serializer_class = AssignmentTaskSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        # 학생이면 본인 과제만
        if hasattr(user, 'profile'):
            return AssignmentTask.objects.filter(student=user.profile)
        
        # Teacher: Allow filtering by student_id
        queryset = AssignmentTask.objects.filter(student__user__is_active=True)
        scope = self.request.query_params.get('scope', 'my')
        if scope == 'my':
            from django.db.models import Q
            queryset = queryset.filter(Q(student__syntax_teacher=user) | Q(student__reading_teacher=user) | Q(student__extra_class_teacher=user)).distinct()
        student_id = self.request.query_params.get('student_id')
        if student_id:
            queryset = queryset.filter(student_id=student_id)
        return queryset

    def perform_create(self, serializer):
        user = self.request.user
        instance = None
        
        if user.is_staff:
            # Teacher creating assignment for student
            instance = serializer.save(teacher=user)
        else:
            # Student creating assignment
            if hasattr(user, 'profile'):
                 instance = serializer.save(student=user.profile)
            else:
                 instance = serializer.save()

        # [NEW] Auto-link to ClassLog if exists on the same day (based on Due Date)
        # This helps grouping "Ad-hoc" assignments under today's class if available.
        if instance and not instance.origin_log and instance.due_date:
            try:
                target_date = timezone.localtime(instance.due_date).date()
                # Find a log for this student on that date
                log = ClassLog.objects.filter(student=instance.student, date=target_date).first()
                if log:
                    instance.origin_log = log
                    instance.save(update_fields=['origin_log'])
            except Exception:
                pass # Fail silently if timezone conversion fails or other issue

    @action(detail=True, methods=['post'])
    def submit(self, request, pk=None):
        print(f"Submit Request for Task {pk}")
        task = self.get_object()
        student_profile = request.user.profile
        print(f"User: {request.user}, Student: {student_profile}")
        
        if task.student != student_profile:
            print("Error: Task student mismatch")
            return Response({'error': '본인의 과제만 제출할 수 있습니다.'}, status=status.HTTP_403_FORBIDDEN)
            
        files = request.FILES.getlist('images')
        if not files:
            single = request.FILES.get('image') or request.FILES.get('evidence_image')
            if single:
                files = [single]
        
        print(f"Files received: {len(files)}")
        if not files:
            print("Error: No files")
            return Response({'error': 'Please attach an image.'}, status=status.HTTP_400_BAD_REQUEST)
            
        submission, created = AssignmentSubmission.objects.get_or_create(task=task, student=student_profile)
        submission.image = files[0]
        submission.status = AssignmentSubmission.Status.PENDING
        submission.teacher_comment = ''
        submission.reviewed_at = None
        submission.submitted_at = timezone.now()
        submission.save()

        AssignmentSubmissionImage.objects.filter(submission=submission).delete()
        try:
            for upload in files:
                print(f"Saving image: {upload.name}, size: {upload.size}")
                AssignmentSubmissionImage.objects.create(
                    submission=submission,
                    image=upload,
                )
        except Exception as e:
            print(f"Error saving images: {e}")
            return Response({'error': str(e)}, status=status.HTTP_400_BAD_REQUEST)
        
        task.is_completed = False
        task.completed_at = None
        task.is_rejected = False
        task.resubmission_deadline = None
        task.save(update_fields=['is_completed', 'completed_at', 'is_rejected', 'resubmission_deadline'])
        
        print("Submit Success")
        return Response({'status': 'submitted'}, status=status.HTTP_200_OK)

    @action(detail=True, methods=['post'])
    def review(self, request, pk=None):
        task = self.get_object()
        if not request.user.is_staff:
            return Response({'error': 'Only staff can review submissions.'}, status=status.HTTP_403_FORBIDDEN)

        try:
            submission = task.submission
        except AssignmentSubmission.DoesNotExist:
            return Response({'error': 'No submission to review.'}, status=status.HTTP_400_BAD_REQUEST)

        status_val = request.data.get('status')
        if status_val not in [
            AssignmentSubmission.Status.APPROVED,
            AssignmentSubmission.Status.REJECTED,
        ]:
            return Response({'error': 'Invalid status.'}, status=status.HTTP_400_BAD_REQUEST)

        comment = request.data.get('teacher_comment') or ''
        deadline_str = request.data.get('resubmission_deadline')
        deadline = None
        if status_val == AssignmentSubmission.Status.REJECTED and deadline_str:
            try:
                deadline = date.fromisoformat(deadline_str)
            except ValueError:
                return Response(
                    {'error': 'Invalid resubmission_deadline. Use YYYY-MM-DD.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        new_due_date = None
        if status_val == AssignmentSubmission.Status.REJECTED and deadline:
            due_time = dt_time(hour=23, minute=59)
            if task.due_date:
                due_time = task.due_date.timetz()
            new_due_date = datetime.combine(deadline, due_time)
            if task.due_date and task.due_date.tzinfo and new_due_date.tzinfo is None:
                new_due_date = new_due_date.replace(tzinfo=task.due_date.tzinfo)

        submission.status = status_val
        submission.teacher_comment = comment
        submission.reviewed_at = timezone.now()
        submission.save(update_fields=['status', 'teacher_comment', 'reviewed_at'])

        if status_val == AssignmentSubmission.Status.APPROVED:
            task.is_completed = True
            task.completed_at = timezone.now()
            task.is_rejected = False
            task.resubmission_deadline = None
        else:
            task.is_completed = False
            task.completed_at = None
            task.is_rejected = True
            task.resubmission_deadline = deadline
            if new_due_date:
                task.due_date = new_due_date

        if new_due_date and task.origin_log:
            task.origin_log.hw_due_date = new_due_date
            task.origin_log.save(update_fields=['hw_due_date'])

        update_fields = ['is_completed', 'completed_at', 'is_rejected', 'resubmission_deadline']
        if new_due_date:
            update_fields.append('due_date')
        task.save(update_fields=update_fields)

        return Response({'status': submission.status}, status=status.HTTP_200_OK)
class AttendanceViewSet(viewsets.ModelViewSet):
    """
    출석 조회 API (읽기 전용)
    """
    serializer_class = AttendanceSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        
        # Staff: View all (with filters)
        if user.is_staff:
            queryset = Attendance.objects.all().order_by('-date')
            student_id = self.request.query_params.get('student_id')
            date = self.request.query_params.get('date')
            
            if student_id:
                queryset = queryset.filter(student_id=student_id)
            if date:
                queryset = queryset.filter(date=date)
            return queryset

        if hasattr(user, 'profile'):
            return Attendance.objects.filter(student=user.profile).order_by('-date')
        return Attendance.objects.none()

    def create(self, request, *args, **kwargs):
        """
        [Fix] IntegrityError 방지: 이미 해당 날짜에 기록이 있으면 업데이트
        """
        student_id = request.data.get('student_id')
        date = request.data.get('date', timezone.now().date())
        status_val = request.data.get('status', 'PRESENT')
        
        # serializer validation will run via update_or_create implicitly if called manually,
        # but here we use model level update_or_create for convenience.
        # Alternatively, find instance first.
        
        try:
            student_profile = StudentProfile.objects.get(id=student_id)
        except StudentProfile.DoesNotExist:
             return Response({'error': 'Student not found'}, status=status.HTTP_404_NOT_FOUND)

        obj, created = Attendance.objects.update_or_create(
            student=student_profile,
            date=date,
            defaults={
                'status': status_val,
                'check_in_time': request.data.get('check_in_time'),
                'left_at': request.data.get('left_at'),
            }
        )
        
        serializer = self.get_serializer(obj)
        headers = self.get_success_headers(serializer.data)
        return Response(serializer.data, status=status.HTTP_200_OK if not created else status.HTTP_201_CREATED, headers=headers)

    @action(detail=False, methods=['post'])
    def check(self, request):
        """
        Smart Kiosk Check-in/out
        - Input: phone_number (11 digits)
        - Logic:
          1. Find student (exact match or stripped dashes)
          2. Check today's record
          3. None -> Create (PRESENT, check_in_time=now) -> Return "등원"
          4. Exists & left_at is None -> Update (left_at=now) -> Return "하원"
          5. Exists & left_at Exists -> Update (left_at=now) -> Return "하원 (갱신)"
        """
        phone = request.data.get('phone_number', '').strip().replace('-', '')
        if not phone:
             return Response({'error': 'Please provide phone_number.'}, status=status.HTTP_400_BAD_REQUEST)

        # 1. Find Student
        # Try finding by exact phone, or stripped
        # StudentProfile stores phone_number. Format might vary.
        # Let's try flexible search?
        # For now, simplistic approach:
        
        student = StudentProfile.objects.filter(phone_number__replace='-', __contains=phone).first()
        # Django lookup doesn't support 'replace' directly like that easily without annotations.
        # Fallback: Filter by phone_number ending with input?
        # Or just standard filter if clean.
        
        # Better: Search by exact match first, then formatted.
        student = StudentProfile.objects.filter(phone_number=phone).first()
        if not student:
            # Try with dashes? 010-1234-5678
            if len(phone) == 11:
                formatted = f"{phone[:3]}-{phone[3:7]}-{phone[7:]}"
                student = StudentProfile.objects.filter(phone_number=formatted).first()
        
        if not student:
            return Response({'error': '학생을 찾을 수 없습니다. (핸드폰 번호 확인)'}, status=status.HTTP_404_NOT_FOUND)

        today = timezone.now().date()
        now = timezone.now()

        # 2. Check Record
        attendance = Attendance.objects.filter(student=student, date=today).first()
        
        msg = ""
        mode = ""

        if not attendance:
            # Check-in
            Attendance.objects.create(
                student=student,
                date=today,
                status='PRESENT',
                check_in_time=now
            )
            msg = f"{student.name} 학생 등원했습니다."
            mode = "IN"
        else:
            # Check-out (or Update)
            attendance.left_at = now
            attendance.save(update_fields=['left_at'])
            msg = f"{student.name} 학생 하원했습니다."
            mode = "OUT"

        return Response({'message': msg, 'mode': mode, 'student_name': student.name}, status=status.HTTP_200_OK)

class ClassLogViewSet(viewsets.ModelViewSet):
    """
    수업 일지 API (조회/생성)
    """
    from .serializers import ClassLogSerializer
    serializer_class = ClassLogSerializer
    permission_classes = [permissions.IsAuthenticated]

    def _is_subject_teacher(self, user, student, subject):
        subject = (subject or '').upper()
        if subject == 'SYNTAX':
            return student.syntax_teacher_id == user.id
        if subject == 'READING':
            return student.reading_teacher_id == user.id
        if subject == 'GRAMMAR':
            return student.extra_class_teacher_id == user.id
        return False

    def _ensure_write_permission(self, user, student, subject, log=None):
        if not user.is_staff:
            raise PermissionDenied('수업일지는 선생님만 작성할 수 있습니다.')
        if log and log.teacher_id == user.id:
            return
        if not self._is_subject_teacher(user, student, subject):
            raise PermissionDenied('해당 과목 담당 선생님만 일지를 작성할 수 있습니다.')

    def get_queryset(self):
        user = self.request.user
        # Student: Own logs
        if hasattr(user, 'profile'):
            return ClassLog.objects.filter(student=user.profile).order_by('-date')
        # Staff: All logs (or filter by query)
        if user.is_staff:
             queryset = ClassLog.objects.all().order_by('-date')
             student_id = self.request.query_params.get('student_id')
             subject = self.request.query_params.get('subject') # [NEW]
             if student_id:
                 queryset = queryset.filter(student_id=student_id)
             if subject:
                 queryset = queryset.filter(subject=subject)

             # [NEW] Date Filter
             date_param = self.request.query_params.get('date')
             if date_param:
                 queryset = queryset.filter(date=date_param)

             return queryset
             return queryset
        return ClassLog.objects.none()

    def create(self, request, *args, **kwargs):
        student_id = request.data.get('student')
        subject = request.data.get('subject')
        if not student_id or not subject:
            return Response(
                {'error': 'student and subject are required.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        try:
            student = StudentProfile.objects.get(id=student_id)
        except StudentProfile.DoesNotExist:
            return Response({'error': 'Student not found.'}, status=status.HTTP_404_NOT_FOUND)

        self._ensure_write_permission(request.user, student, subject)
        return super().create(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.save(teacher=self.request.user)

    def update(self, request, *args, **kwargs):
        log = self.get_object()
        self._ensure_write_permission(request.user, log.student, log.subject, log=log)
        return super().update(request, *args, **kwargs)

    def partial_update(self, request, *args, **kwargs):
        log = self.get_object()
        self._ensure_write_permission(request.user, log.student, log.subject, log=log)
        return super().partial_update(request, *args, **kwargs)

class TemporaryScheduleViewSet(viewsets.ModelViewSet):
    """
    보강/일정 변경 관리 API (조회/생성/삭제)
    """
    from .serializers import TemporaryScheduleSerializer
    serializer_class = TemporaryScheduleSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        if hasattr(user, 'profile'):
            return TemporarySchedule.objects.filter(student=user.profile).order_by('-created_at')
        if user.is_staff:
            queryset = TemporarySchedule.objects.all().order_by('-created_at')
            student_id = self.request.query_params.get('student_id')
            if student_id:
                queryset = queryset.filter(student=student_id)
            return queryset
        return TemporarySchedule.objects.none()

class TextbookViewSet(viewsets.ModelViewSet):
    """
    교재 관리 API
    """
    queryset = Textbook.objects.all()
    serializer_class = TextbookSerializer
    permission_classes = [permissions.IsAuthenticated] # Or AllowAny allow read?
    
    def get_queryset(self):
        # Category filtering support: /api/v1/academy/textbooks/?category=SYNTAX
        queryset = super().get_queryset()
        category = self.request.query_params.get('category')
        if category:
            queryset = queryset.filter(category=category)
        return queryset
