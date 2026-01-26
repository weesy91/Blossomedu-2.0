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

            classes_data = []
            seen_keys = set()
            for c in classes:
                time_str = c.start_time.strftime('%H:%M') if c.start_time else ''
                key = (c.branch_id, c.day, time_str, c.class_type)
                if key in seen_keys:
                    continue
                seen_keys.add(key)
                classes_data.append({
                    'id': c.id,
                    'name': str(c),
                    'branch_id': c.branch_id,
                    'day': c.day,
                    'time': time_str,
                    'type': c.class_type # Use actual DB field
                })

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

        if not user.is_staff and hasattr(user, 'profile'):
            return queryset.filter(user=user)

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

    @action(detail=True, methods=['post'])
    def reset_password(self, request, pk=None):
        """학생 비밀번호 재설정"""
        student = self.get_object()
        new_password = request.data.get('password')
        
        if not new_password:
            return Response({'error': '비밀번호를 입력하세요'}, status=status.HTTP_400_BAD_REQUEST)
        
        if len(new_password) < 4:
            return Response({'error': '비밀번호는 4자 이상이어야 합니다'}, status=status.HTTP_400_BAD_REQUEST)
        
        student.user.set_password(new_password)
        student.user.save()
        
        return Response({'message': '비밀번호가 재설정되었습니다'})

    @action(detail=False, methods=['post'])
    def upload_excel(self, request):
        """
        엑셀 파일 일괄 업로드
        형식: '수강생 관리' 시트 (Sample.xlsx 참조)
        """
        try:
            file = request.FILES.get('file')
            if not file:
                return Response({'error': '파일이 제공되지 않았습니다.'}, status=status.HTTP_400_BAD_REQUEST)

            import pandas as pd
            import re
            from datetime import datetime, time
            import traceback
            
            df = pd.read_excel(file, engine='openpyxl')
            
            # Column Mapping (Excel Col -> Variable)
            # 이름(학교), 담당선생님, 수업요일, 수업시간, 독해선생님, 독해수업요일, 독해수업시간, 입/퇴원, 학생이름, 학교, 학년, 학생 H.P, 어머니 H.P, 아버지 H.P, 주소
            
            created_count = 0
            updated_count = 0
            errors = []
            
            # Grade Mapping
            GRADE_MAP = {
                '초1': 1, '초2': 2, '초3': 3, '초4': 4, '초5': 5, '초6': 6,
                '중1': 7, '중2': 8, '중3': 9,
                '고1': 10, '고2': 11, '고3': 12, '졸업': 13
            }
            
            # Day Mapping
            DAY_MAP = {
                '월요일': 'Mon', '화요일': 'Tue', '수요일': 'Wed', '목요일': 'Thu', '금요일': 'Fri', '토요일': 'Sat', '일요일': 'Sun',
                '월': 'Mon', '화': 'Tue', '수': 'Wed', '목': 'Thu', '금': 'Fri', '토': 'Sat', '일': 'Sun'
            }

            for index, row in df.iterrows():
                try:
                    # 1. Basic Validation
                    name = str(row['학생이름']).strip()
                    if not name or name == 'nan': continue
                    
                    status_val = str(row['입/퇴원']).strip()
                    # Skip '퇴원' users? Or mark as inactive?
                    # Request was "create accounts". Let's create even if inactive, but set is_active=False?
                    # User likely wants Active students primarily.
                    is_active = (status_val == '입학')

                    phone = str(row['학생 H.P']).strip()
                    if not phone or phone == 'nan': 
                        # Phone is required for ID
                        continue

                    # 2. User ID / Phone Parsing
                    # 010-1234-5678 -> 01012345678
                    clean_phone = re.sub(r'[^0-9]', '', phone)
                    if not clean_phone: continue

                    username = clean_phone
                    
                    user, created = User.objects.get_or_create(username=username)
                    if created:
                        # Default Password: Last 4 digits or '1234'
                        pw = clean_phone[-4:] if len(clean_phone) >= 4 else '1234'
                        user.set_password(pw)
                        created_count += 1
                    else:
                        updated_count += 1
                    
                    user.is_active = is_active # Sync status
                    user.save()

                    # 3. Create/Update Profile
                    # Ensure profile exists (signal should create it, but safe to get_or_create)
                    if not hasattr(user, 'profile'):
                        StudentProfile.objects.create(user=user, name=name)
                    
                    profile = user.profile
                    profile.name = name
                    profile.phone_number = phone
                    
                    # 4. School
                    school_name = str(row['학교']).strip()
                    if school_name and school_name != 'nan':
                        school, _ = School.objects.get_or_create(name=school_name)
                        profile.school = school
                        # Branch assignment? We can infer from Staff who is uploading? 
                        # For now, if user has branch assignment, use that?
                        # Or if school has branch?
                        if hasattr(request.user, 'staff_profile') and request.user.staff_profile.branch:
                             profile.branch = request.user.staff_profile.branch
                    
                    # 5. Grade
                    grade_str = str(row['학년']).strip()
                    # Extract grade part if mixed (e.g. '고1(휴학)')
                    # Simple map check
                    if grade_str in GRADE_MAP:
                        profile.base_grade = GRADE_MAP[grade_str]
                        profile.base_year = timezone.now().year # Reset base year to now for correct calculation
                    
                    # 6. Parents
                    mom_phone = str(row['어머니 H.P']).strip()
                    if mom_phone and mom_phone != 'nan':
                        profile.parent_phone_mom = mom_phone
                        
                    dad_phone = str(row['아버지 H.P']).strip()
                    if dad_phone and dad_phone != 'nan':
                        profile.parent_phone_dad = dad_phone
                        
                    # 7. Address & Memo
                    addr = str(row['주소']).strip()
                    if addr and addr != 'nan':
                        profile.address = addr
                        
                    memo = str(row['특이사항']).strip()
                    if memo and memo != 'nan':
                        profile.memo = memo

                    # 8. Start Date
                    start_date_val = row['수업시작일']
                    if pd.notnull(start_date_val):
                         # Timestamp to Date
                         try:
                            if hasattr(start_date_val, 'date'):
                                profile.start_date = start_date_val.date()
                         except:
                            pass

                    # 9. Schedule Logic (Try to match ClassTime)
                    def parse_time_custom(time_val, is_weekend):
                        try:
                            if pd.isna(time_val) or str(time_val).strip() == '':
                                return None
                            
                            h, m = 0, 0
                            if isinstance(time_val, (datetime, time)):
                                t = time_val if isinstance(time_val, time) else time_val.time()
                                h, m = t.hour, t.minute
                            else:
                                # String parse
                                time_str = str(time_val).strip()
                                parts = time_str.replace(':', '.').split('.')
                                if len(parts) >= 2:
                                    h = int(parts[0])
                                    m = int(parts[1])
                                else:
                                    return None

                            # Apply Logic
                            if is_weekend:
                                # Weekend: 24-hour format (Trust the number)
                                pass
                            else:
                                # Weekday: 12-hour format (Implicitly PM)
                                # If 1~11, assume PM (add 12). 
                                # Exception: 12 is usually 12 PM (noon) or 12 AM (midnight)?
                                # Academy context: 12 is likely noon (12:00). 
                                # 1, 2, 3... are 13, 14, 15...
                                if 0 < h < 12:
                                    h += 12
                            
                            return time(h, m)
                        except:
                            return None

                    # Syntax
                    syntax_day_str = str(row['수업요일']).strip()
                    
                    if syntax_day_str in DAY_MAP:
                        day_code = DAY_MAP[syntax_day_str]
                        is_weekend = day_code in ['Sat', 'Sun']
                        
                        time_obj = parse_time_custom(row['수업시간'], is_weekend)
                        
                        if time_obj:
                            # Find ClassTime
                            cts = ClassTime.objects.filter(
                                day=day_code,
                                class_type='SYNTAX',
                                start_time=time_obj
                            )
                            if cts.exists():
                                profile.syntax_class = cts.first()

                    # Reading
                    reading_day_str = str(row['독해수업요일']).strip()
                    
                    if reading_day_str in DAY_MAP:
                        day_code = DAY_MAP[reading_day_str]
                        is_weekend = day_code in ['Sat', 'Sun']

                        time_obj = parse_time_custom(row['독해수업시간'], is_weekend)

                        if time_obj:
                            cts = ClassTime.objects.filter(
                                day=day_code,
                                class_type='READING',
                                start_time=time_obj
                            )
                            if cts.exists():
                                profile.reading_class = cts.first()

                    profile.save()

                except Exception as row_e:
                    errors.append(f"Row {index}: {str(row_e)}")

            return Response({
                'message': f'Upload Complete. Created: {created_count}, Updated: {updated_count}',
                'errors': errors[:10] # Return first 10 errors
            })
        except Exception as e:
            try:
                import traceback
                traceback.print_exc()
            except: pass
            return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """
        활성 학생 통계 (분원별 수)
        - 개발자(Superuser): 전체 분원 통계
        - 원장/부원장: 본인 분원 통계
        - 그 외(강사 등): 권한 없음 (빈 값)
        """
        from django.db.models import Count
        user = request.user
        
        # 0. Initial Check
        if not hasattr(user, 'staff_profile') and not user.is_superuser:
            return Response({'total': 0, 'breakdown': []})

        queryset = StudentProfile.objects.filter(user__is_active=True)
        
        # 1. Permission Logic
        if user.is_superuser:
            # View All
            pass 
        else:
            profile = user.staff_profile
            # Only Principal/Vice can see stats
            if profile.position not in ['PRINCIPAL', 'VICE']:
                 return Response({'total': 0, 'breakdown': []})

            if profile.branch:
                queryset = queryset.filter(branch=profile.branch)
            else:
                # Principal with no branch? Show nothing safe
                return Response({'total': 0, 'breakdown': []})

        stats = queryset.values('branch__name').annotate(count=Count('id')).order_by('branch__name')
        
        # Reform data to list
        data = []
        total_active = 0
        for s in stats:
            b_name = s['branch__name'] or '지점 미정'
            cnt = s['count']
            data.append({'branch': b_name, 'count': cnt})
            total_active += cnt
            
        return Response({
            'total': total_active,
            'breakdown': data
        })


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
