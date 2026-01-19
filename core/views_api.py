from rest_framework import viewsets, permissions, status, filters
from rest_framework.decorators import action
from rest_framework.response import Response
from django.db.models import Q
from .models import Message, School, StudentProfile, StaffProfile
from .models import Message, School, StudentProfile, StaffProfile
from .models.announcement import Announcement # [NEW]
from .serializers import MessageSerializer, StudentProfileSerializer, StaffProfileSerializer, AnnouncementSerializer # [NEW]
from django.utils import timezone

class MessageViewSet(viewsets.ModelViewSet):
    """
    메시지 API
    """
    serializer_class = MessageSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        # 내가 보냈거나 받은 메시지 전체
        return Message.objects.filter(
            Q(sender=user) | Q(receiver=user)
        ).order_by('-sent_at')

    def perform_create(self, serializer):
        serializer.save(sender=self.request.user)
        
    def retrieve(self, request, *args, **kwargs):
        instance = self.get_object()
        # 받는 사람이 내용을 확인하면 읽음 처리
        if instance.receiver == request.user and not instance.read_at:
            instance.read_at = timezone.now()
            instance.save()
        return super().retrieve(request, *args, **kwargs)

class AnnouncementViewSet(viewsets.ModelViewSet):
    """
    학원 공지사항 API
    - 읽기: 누구나? (현재는 인증된 사용자)
    - 쓰기: 스태프(선생님/관리자)만 가능
    """
    queryset = Announcement.objects.all().order_by('-is_active', '-created_at')
    serializer_class = AnnouncementSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_create(self, serializer):
        serializer.save(author=self.request.user)

    def get_queryset(self):
        qs = super().get_queryset()
        # 학생이면 활성화된 공지만 보임
        if not self.request.user.is_staff:
             qs = qs.filter(is_active=True)
        return qs

class SchoolViewSet(viewsets.ViewSet):
    """
    학교 목록 조회 API (지점별 필터링 지원)
    """
    permission_classes = [permissions.IsAuthenticated]

    def list(self, request):
        branch_id = request.query_params.get('branch_id')
        queryset = School.objects.all().order_by('name')

        # [Auto-Detect logic]
        if not branch_id and hasattr(request.user, 'staff_profile') and request.user.staff_profile.branch:
             branch_id = request.user.staff_profile.branch.id

        if branch_id:
            # 해당 지점의 학생이 재학 중인 학교만 필터링
            # related_name이 명시되지 않았을 수 있으므로 'studentprofile' 사용
            queryset = queryset.filter(studentprofile__branch_id=branch_id).distinct()
        
        data = [{'id': s.id, 'name': s.name} for s in queryset]
        return Response(data)

from django.contrib.auth.models import User
from .models import StaffProfile, StudentProfile, ClassTime, Branch
from .models.users import StudentUser

class StudentRegistrationViewSet(viewsets.ViewSet):
    """
    학생 등록 API (선생님용)
    """
    permission_classes = [permissions.IsAuthenticated] # Teacher only ideally

    @action(detail=False, methods=['get'])
    def metadata(self, request):
        """
        등록 폼에 필요한 메타데이터 반환 (학교, 선생님, 시간표 등)
        """

        user = request.user
        branch = None
        if hasattr(user, 'staff_profile') and user.staff_profile.branch:
            branch = user.staff_profile.branch

        try:
            # 1. Schools
            schools = School.objects.all()
            if branch:
                schools = schools.filter(branches=branch)

            # 2. Teachers (Syntax, Reading, Extra)
            teachers = User.objects.filter(is_active=True, staff_profile__isnull=False)
            if branch:
                teachers = teachers.filter(staff_profile__branch=branch)

            # 3. ClassTimes
            classes = ClassTime.objects.all().order_by('day', 'start_time')
            if branch:
                classes = classes.filter(Q(branch=branch) | Q(branch__isnull=True))

            # 4. Booked Syntax Slots (For 1:1 locking)
            booked_slots = StudentProfile.objects.filter(
                syntax_teacher__isnull=False, 
                syntax_class__isnull=False
            ).values('syntax_teacher_id', 'syntax_class_id', 'syntax_class__day') # Added day for easier debugging if needed

            classes_data = [{
                'id': c.id,
                'name': str(c),
                'branch_id': c.branch_id,
                'day': c.day,
                'time': c.start_time.strftime('%H:%M') if c.start_time else '',
                'type': c.class_type # Use actual DB field
            } for c in classes]

            # 5. Branches
            branches = Branch.objects.all()
            if branch: # user specific branch
                 branches = branches.filter(id=branch.id)
            
            data = {
                'branches': [{'id': b.id, 'name': b.name} for b in branches],
                'schools': [{'id': s.id, 'name': s.name, 'branches': list(s.branches.values_list('id', flat=True))} for s in schools],
                'teachers': [{
                    'id': t.id,
                    'name': t.staff_profile.name or t.username,
                    'is_syntax': t.staff_profile.is_syntax_teacher,
                    'is_reading': t.staff_profile.is_reading_teacher,
                    'position': t.staff_profile.position
                } for t in teachers],
                'classes': classes_data,
                'booked_syntax_slots': list(booked_slots), # [NEW]
                'default_branch_id': branch.id if branch else None,
                'default_branch_name': branch.name if branch else "지점 미정",
            }
            return Response(data)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    def create(self, request):
        try:
            data = request.data
            
            # 1. User 생성
            username = data.get('username')
            password = data.get('password')
            if User.objects.filter(username=username).exists():
                return Response({'error': '이미 존재하는 ID입니다.'}, status=status.HTTP_400_BAD_REQUEST)
            
            user = User.objects.create_user(username=username, password=password)
            
            # 2. Profile 업데이트 (post_save signal로 이미 생성됨)
            profile = StudentProfile.objects.get(user=user) # Assuming StudentProfile is linked via user.profile or similar
            profile.name = data.get('name')
            profile.phone_number = data.get('phone_number', '')
            profile.parent_phone_mom = data.get('parent_phone_mom', '')
            profile.parent_phone_dad = data.get('parent_phone_dad', '') # [NEW]
            
            if data.get('start_date'): # [NEW]
                profile.start_date = data.get('start_date')

            if data.get('school_id'):
                profile.school_id = data.get('school_id')
            
            if data.get('grade'):
                profile.base_grade = data.get('grade')
            
            if data.get('branch_id'):
                profile.branch_id = data.get('branch_id')
            
            # 선생님 배정
            if data.get('syntax_teacher_id'):
                profile.syntax_teacher_id = data.get('syntax_teacher_id')
            if data.get('reading_teacher_id'):
                profile.reading_teacher_id = data.get('reading_teacher_id')
            if data.get('extra_teacher_id'):
                profile.extra_class_teacher_id = data.get('extra_teacher_id')
            
            if data.get('extra_class_category'):
                profile.extra_class_category = data.get('extra_class_category')
                
            # 시간표 배정
            if data.get('syntax_class_id'):
                profile.syntax_class_id = data.get('syntax_class_id')
            if data.get('reading_class_id'):
                profile.reading_class_id = data.get('reading_class_id')
            if data.get('extra_class_id'):
                profile.extra_class_id = data.get('extra_class_id')
            
            profile.save()
            
            return Response({'message': '학생 등록 완료', 'student_id': profile.id}, status=status.HTTP_201_CREATED)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

class StaffRegistrationViewSet(viewsets.ViewSet):
    """
    선생님 등록 API (원장/관리자용 -> 공개 가입으로 변경)
    """
    permission_classes = [permissions.AllowAny]

    @action(detail=False, methods=['get'])
    def metadata(self, request):
        """
        선생님 등록 폼 메타데이터 (지점, 직책 옵션 등)
        """
        try:
            # 1. Branches
            branches = Branch.objects.all().values('id', 'name')
            
            # 2. Position Choices
            positions = [
                {'value': code, 'label': label} 
                for code, label in StaffProfile.POSITION_CHOICES
            ]

            return Response({
                'branches': list(branches),
                'positions': positions,
            })
        except Exception as e:
             return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(detail=False, methods=['post'])
    def create_staff(self, request):
        try:
            data = request.data
            username = data.get('username')
            password = data.get('password')
            
            if User.objects.filter(username=username).exists():
                return Response({'error': '이미 존재하는 ID입니다.'}, status=status.HTTP_400_BAD_REQUEST)
            
            # Create User
            # [Fix] is_staff=True를 create_user에 바로 전달하여 signal에서 StudentProfile 생성을 방지함.
            user = User.objects.create_user(username=username, password=password, email=data.get('email', ''), is_staff=True)
            # user.is_staff = True (No longer needed separately)
            # user.save()

            # Create StaffProfile
            branch_id = data.get('branch_id')
            
            profile = StaffProfile.objects.create(
                user=user,
                name=data.get('name'),
                branch_id=branch_id,
                position=data.get('position', 'TEACHER'),
                join_date=data.get('join_date'),
                phone_number=data.get('phone_number', ''),
                memo=data.get('memo', ''),
                is_syntax_teacher=data.get('is_syntax', False),
                is_reading_teacher=data.get('is_reading', False)
            )
            
            return Response({'message': '선생님 등록 완료', 'staff_id': profile.id}, status=status.HTTP_201_CREATED)
            
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

class StudentManagementViewSet(viewsets.ModelViewSet):
    """
    학생 관리 API (전체 목록, 검색)
    """
    serializer_class = StudentProfileSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter]
    search_fields = ['name', 'user__username', 'phone_number']

    def get_queryset(self):
        user = self.request.user
        scope = self.request.query_params.get('scope')

        # Base Queryset
        queryset = StudentProfile.objects.filter(user__is_staff=False)

        # 0. Force 'My Students' Scope
        if scope == 'my':
            return queryset.filter(
                Q(syntax_teacher=user) | Q(reading_teacher=user) | Q(extra_class_teacher=user),
                user__is_active=True 
            ).distinct().order_by('-user__is_active', 'base_grade', 'name')

        # 1. Check Staff Profile (Priority over Superuser)
        try:
            profile = user.staff_profile
        except:
            profile = None

        if profile:
            # Principal / Vice / TA: View All Students in Branch
            # Even if Superuser, if assigned to a branch, restrict it!
            if profile.position in ['PRINCIPAL', 'VICE', 'TA']:
                if profile.branch:
                    queryset = queryset.filter(branch=profile.branch)
                elif not user.is_superuser:
                    # Manager without branch & Not Superuser => View None
                    return StudentProfile.objects.none()
            
            # Teacher: View Assigned Students Only (Unless Superuser?)
            elif not user.is_superuser:
                queryset = queryset.filter(
                    Q(syntax_teacher=user) | Q(reading_teacher=user) | Q(extra_class_teacher=user)
                ).distinct()
        
        # 2. Superuser (Fallback if no profile restriction applied)
        elif user.is_superuser:
            pass # View All
            
        else:
             # No Profile, Not Superuser => None
             return StudentProfile.objects.none()

        # Day Filtering (Common)
        day = self.request.query_params.get('day') # e.g. 'Mon'
        if day:
            queryset = queryset.filter(
                Q(syntax_class__day=day) | 
                Q(reading_class__day=day) | 
                Q(extra_class__day=day)
            ).distinct()
            
        return queryset.order_by('-user__is_active', 'base_grade', 'name')

    def perform_destroy(self, instance):
        # Profile 삭제 시 User도 함께 삭제 (Cascade로 Profile도 자동 삭제됨)
        instance.user.delete()

class StaffManagementViewSet(viewsets.ModelViewSet):
    """
    강사 관리 API (전체 목록, 검색)
    """
    serializer_class = StaffProfileSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter]
    search_fields = ['name', 'user__username']
    
    def get_queryset(self):
        user = self.request.user
        queryset = StaffProfile.objects.all().order_by('position', 'name')
        
        # 1. Check Staff Profile (Priority over Superuser)
        try:
            profile = user.staff_profile
        except:
            profile = None

        if profile and profile.position in ['PRINCIPAL', 'VICE'] and profile.branch:
             queryset = queryset.filter(branch=profile.branch)
        
        elif user.is_superuser:
             pass
        
        else:
             # Normal Teacher cannot see Staff list? Or just themselves?
             # Assuming Teachers shouldn't manage staff usually.
             if profile:
                 return queryset.filter(user=user) # Only self
             return StaffProfile.objects.none()
             
        return queryset

    def perform_destroy(self, instance):
        instance.user.delete()

from .models import Branch, School
from .serializers import BranchSerializer, SchoolSerializer

class BranchManagementViewSet(viewsets.ModelViewSet):
    queryset = Branch.objects.all()
    serializer_class = BranchSerializer
    permission_classes = [permissions.IsAuthenticated]

class SchoolManagementViewSet(viewsets.ModelViewSet):
    queryset = School.objects.all()
    serializer_class = SchoolSerializer
    permission_classes = [permissions.IsAuthenticated]
