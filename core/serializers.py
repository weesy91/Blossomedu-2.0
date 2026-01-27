from rest_framework import serializers
from .models import Message, StudentProfile
from .models.announcement import Announcement # [NEW]
from django.contrib.auth.models import User

class UserSimpleSerializer(serializers.ModelSerializer):
    """
    메시지 전송 시 보여줄 간단한 유저 정보
    """
    name = serializers.SerializerMethodField()
    
    class Meta:
        model = User
        fields = ['id', 'username', 'name']
        
    def get_name(self, obj):
        if hasattr(obj, 'profile'):
            return obj.profile.name
        elif hasattr(obj, 'staff_profile'):
            return obj.staff_profile.name or obj.username
        return obj.username

class MessageSerializer(serializers.ModelSerializer):
    sender_info = UserSimpleSerializer(source='sender', read_only=True)
    receiver_info = UserSimpleSerializer(source='receiver', read_only=True)
    
    class Meta:
        model = Message
        fields = '__all__'
        read_only_fields = ['sent_at', 'read_at', 'sender']

class AnnouncementSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source='author.profile.name', read_only=True, default='')

    class Meta:
        model = Announcement
        fields = ['id', 'title', 'content', 'image', 'author', 'author_name', 'created_at', 'is_active']
        read_only_fields = ['author', 'created_at']

    def to_representation(self, instance):
        ret = super().to_representation(instance)
        # Fallback author name lookup if profile doesn't exist or is different type
        if not ret['author_name']:
             if hasattr(instance.author, 'staff_profile'):
                 ret['author_name'] = instance.author.staff_profile.name
             else:
                 ret['author_name'] = instance.author.username
        return ret

class StudentProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', read_only=True)  # Read-only for display
    new_username = serializers.CharField(write_only=True, required=False)  # Write-only for updates
    grade_display = serializers.CharField(source='current_grade_display', read_only=True)
    branch_name = serializers.CharField(source='branch.name', read_only=True)
    school_name = serializers.CharField(source='school.name', read_only=True)
    class_times = serializers.SerializerMethodField() # [NEW] Integrated class times
    temp_schedules = serializers.SerializerMethodField() # [NEW] Make-up classes

    class Meta:
        model = StudentProfile
        fields = [
            'id', 'username', 'new_username', 'name', 'phone_number', 'parent_phone_mom', 'parent_phone_dad',
            'school_name', 'grade_display', 'branch_name', 'start_date',
            'branch', 'school', 'base_grade',
            'syntax_teacher', 'syntax_class',
            'reading_teacher', 'reading_class',
            'extra_class_teacher', 'extra_class', 'extra_class_category',
            'extra_class_teacher', 'extra_class', 'extra_class_category',
            'is_active',
            'class_times', # [NEW]
            'temp_schedules', # [NEW]
            'log_history' # [NEW]
        ]
        # StudentProfile has start_date.
        extra_kwargs = {
            'join_date': {'read_only': True} 
        }

    is_active = serializers.BooleanField(source='user.is_active', required=False) # [NEW]

    def update(self, instance, validated_data):
        # Handle User update (is_active, username)
        user = instance.user
        user_data = validated_data.pop('user', {})
        
        # Username 변경 처리 (new_username 필드 우선, 그 다음 user dict)
        new_username = validated_data.pop('new_username', None) or user_data.get('username')
        if new_username and new_username != user.username:
            from django.contrib.auth.models import User
            if User.objects.filter(username=new_username).exclude(id=user.id).exists():
                raise serializers.ValidationError({'username': '이미 사용 중인 아이디입니다.'})
            user.username = new_username
        
        if 'is_active' in user_data:
            user.is_active = user_data['is_active']
        
        user.save()
            
        return super().update(instance, validated_data)


    def _should_filter_by_teacher(self):
        request = self.context.get('request')
        if request is None:
            return False
        if not request.user.is_staff:
            return False
        return request.query_params.get('scope') == 'my'

    def _allowed_subjects_for_teacher(self, obj, user):
        allowed = []
        if obj.syntax_teacher_id == user.id:
            allowed.append('SYNTAX')
        if obj.reading_teacher_id == user.id:
            allowed.append('READING')
        if obj.extra_class_teacher_id == user.id:
            allowed.append('GRAMMAR')
        return allowed

    def _get_teacher_name(self, teacher):
        """Helper to get teacher's display name"""
        if teacher is None:
            return None
        if hasattr(teacher, 'staff_profile') and teacher.staff_profile:
            return teacher.staff_profile.name
        return teacher.username

    def get_class_times(self, obj):
        times = []
        filter_by_teacher = self._should_filter_by_teacher()
        user = self.context.get('request').user if filter_by_teacher else None
        if obj.syntax_class and (not filter_by_teacher or obj.syntax_teacher_id == user.id):
            times.append({
                'day': obj.syntax_class.day,
                'start_time': obj.syntax_class.start_time.strftime('%H:%M'),
                'subject': '구문',
                'type': 'SYNTAX',
                'teacher_name': self._get_teacher_name(obj.syntax_teacher)
            })
        if obj.reading_class and (not filter_by_teacher or obj.reading_teacher_id == user.id):
            times.append({
                'day': obj.reading_class.day,
                'start_time': obj.reading_class.start_time.strftime('%H:%M'),
                'subject': '독해',
                'type': 'READING',
                'teacher_name': self._get_teacher_name(obj.reading_teacher)
            })
        if obj.extra_class and (not filter_by_teacher or obj.extra_class_teacher_id == user.id):
            times.append({
                'day': obj.extra_class.day,
                'start_time': obj.extra_class.start_time.strftime('%H:%M'),
                'subject': obj.get_extra_class_category_display(),
                'type': obj.extra_class_category,
                'teacher_name': self._get_teacher_name(obj.extra_class_teacher)
            })
        return times

    def get_temp_schedules(self, obj):
        if not hasattr(obj, 'temp_schedules'):
            return []
        qs = obj.temp_schedules.all()
        
        # [FIX] Relax filtering: Return ALL temp schedules for the student.
        # Previously, if a teacher scheduled a make-up class for a subject they
        # aren't the main teacher for (e.g. subbing), it wouldn't show up.
        # if self._should_filter_by_teacher():
        #     user = self.context.get('request').user
        #     allowed_subjects = self._allowed_subjects_for_teacher(obj, user)
        #     if not allowed_subjects:
        #          return []
        #     qs = qs.filter(subject__in=allowed_subjects)
            
        # Return specific fields needed for planner
        return list(qs.values(
            'id', 'subject', 'is_extra_class', 'original_date', 
            'new_date', 'new_start_time', 'note'
        ))

    # [NEW] Log History for Planner Indicator
    log_history = serializers.SerializerMethodField()

    def get_log_history(self, obj):
        # Return list of dates (YYYY-MM-DD) where a class log exists
        # Optimize: Filter only recent logs (e.g. last 3 months) if needed, 
        # but for now all logs or last 30 days might be enough for planner view.
        # Let's get all distinct dates for simplicity ensuring planner sees them.
        from academy.models import ClassLog
        logs = ClassLog.objects.filter(student=obj).values_list('date', flat=True).distinct()
        return [d.strftime('%Y-%m-%d') for d in logs]

from .models.users import StaffProfile

class StaffProfileSerializer(serializers.ModelSerializer):
    username = serializers.CharField(source='user.username', required=False)
    email = serializers.CharField(source='user.email', required=False)
    user_id = serializers.IntegerField(source='user.id', read_only=True) # [NEW]
    password = serializers.CharField(write_only=True, required=False)
    branch_name = serializers.CharField(source='branch.name', read_only=True)
    position_display = serializers.CharField(source='get_position_display', read_only=True)
    
    managed_teachers = serializers.PrimaryKeyRelatedField(many=True, queryset=User.objects.filter(is_staff=True), required=False) # [NEW]

    class Meta:
        model = StaffProfile
        fields = [
            'id', 'user_id', 'username', 'email', 'password', 'name', 'branch_name', 'position', 'position_display',
            'is_syntax_teacher', 'is_reading_teacher', 'join_date', 'resignation_date',
            'phone_number', 'memo',
            'branch', 'managed_teachers', 'is_active' # [NEW]
        ]
        
    is_active = serializers.BooleanField(source='user.is_active', required=False) # [NEW]

    def update(self, instance, validated_data):
        user = instance.user
        
        # User Update (Username, Email, is_active)
        # [FIX] pop 'user' once and reuse
        user_dict = validated_data.pop('user', {}) 
        
        new_username = user_dict.get('username')
        new_email = user_dict.get('email')
        new_is_active = user_dict.get('is_active')

        # Username Update
        if new_username and new_username != user.username:
            if User.objects.filter(username=new_username).exclude(id=user.id).exists():
                raise serializers.ValidationError({"username": "이미 존재하는 아이디입니다."})
            user.username = new_username
        
        # Email Update
        if new_email is not None:
             user.email = new_email
             
        # is_active Update
        if new_is_active is not None:
            user.is_active = new_is_active

        # Save User if changed
        if new_username or new_email is not None or new_is_active is not None:
            user.save()
            
        # Password Update
        password = validated_data.pop('password', None)
        if password:
            user.set_password(password)
            user.save()

        return super().update(instance, validated_data)

from .models import Branch, School

class BranchSerializer(serializers.ModelSerializer):
    class Meta:
        model = Branch
        fields = '__all__'

class SchoolSerializer(serializers.ModelSerializer):
    branches_details = BranchSerializer(source='branches', many=True, read_only=True)
    
    class Meta:
        model = School
        fields = ['id', 'name', 'region', 'branches', 'branches_details']
        extra_kwargs = {
            'branches': {'required': False} # Optional
        }
