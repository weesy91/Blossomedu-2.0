from django import forms
from django.forms import Select
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import User, Group 
from django.http import HttpResponse 
from django.db.models import Case, When, IntegerField
from .models import School, StudentProfile, ClassTime, Branch, StaffUser, StudentUser, StaffProfile
from .models.popup import Popup
from .models.users import StaffUser, StudentUser, StudentProfile

# ==========================================
# 0. 공통 헬퍼 함수
# ==========================================
def response_popup_close(request, obj, post_url_continue=None):
    """팝업창에서 저장 시 자동으로 창을 닫고 부모창 새로고침"""
    if "_popup" in request.POST:
        return HttpResponse('''<script>window.close();if(window.opener&&!window.opener.closed){window.opener.location.reload();}</script>''')
    return None

# ==========================================
# 1. 지점 & 학교 관리
# ==========================================
@admin.register(Branch)
class BranchAdmin(admin.ModelAdmin):
    list_display = ('name',)
    def response_add(self, request, obj, post_url_continue=None):
        return response_popup_close(request, obj) or super().response_add(request, obj, post_url_continue)

@admin.register(School)
class SchoolAdmin(admin.ModelAdmin):
    list_display = ('name', 'region', 'get_branches')
    search_fields = ('name',)
    list_filter = ('branches',) 
    filter_horizontal = ('branches',)

    def get_branches(self, obj):
        return ", ".join([b.name for b in obj.branches.all()])
    get_branches.short_description = "관련 지점"

    def response_add(self, request, obj, post_url_continue=None):
        return response_popup_close(request, obj) or super().response_add(request, obj, post_url_continue)

# ==========================================
# 2. 수업 시간표 관리
# ==========================================
@admin.register(ClassTime)
class ClassTimeAdmin(admin.ModelAdmin):
    list_display = ('__str__', 'branch', 'day', 'start_time', 'end_time')
    list_filter = ('branch', 'day')
    search_fields = ('day', 'start_time', 'name')
    
    def get_queryset(self, request):
        day_order = Case(
            When(day='Mon', then=0), When(day='Tue', then=1), When(day='Wed', then=2),
            When(day='Thu', then=3), When(day='Fri', then=4), When(day='Sat', then=5),
            When(day='Sun', then=6), output_field=IntegerField(),
        )
        return super().get_queryset(request).annotate(day_order=day_order).order_by('branch', 'day_order', 'start_time')

# ==========================================
# 3. 학생 관리 (계정과 프로필 통합)
# ==========================================

# [NEW] 이게 없어서 에러가 났습니다! (검색용 유령 Admin)
@admin.register(StudentProfile)
class StudentProfileAdmin(admin.ModelAdmin):
    search_fields = ('name', 'school__name', 'phone_number') # 검색 가능하게 설정
    
    # 이 부분이 핵심입니다! 
    # 검색 기능은 살려두되, 관리자 메뉴바에는 보이지 않게 숨깁니다.
    def get_model_perms(self, request):
        return {} 

class StudentProfileValidationForm(forms.ModelForm):
    class Meta:
        model = StudentProfile
        fields = '__all__'

    def clean(self):
        cleaned_data = super().clean()
        instance = self.instance 
        check_list = [
            ('구문', 'syntax_teacher', 'syntax_class'),
            ('추가', 'extra_class_teacher', 'extra_class'),
        ]
        for subject_name, teacher_field, class_field in check_list:
            teacher = cleaned_data.get(teacher_field)
            class_time = cleaned_data.get(class_field)
            if teacher and class_time:
                conflicts = StudentProfile.objects.filter(**{teacher_field: teacher, class_field: class_time})
                if instance.pk: conflicts = conflicts.exclude(pk=instance.pk)
                if conflicts.exists():
                    other_student = conflicts.first().name 
                    teacher_name = teacher.staff_profile.name if hasattr(teacher, 'staff_profile') else teacher.username
                    raise forms.ValidationError(f"⛔ [중복] {teacher_name} 선생님은 '{class_time}' 시간에 이미 '{other_student}' 학생 수업이 있습니다. ({subject_name})")
        return cleaned_data

class StudentProfileInline(admin.StackedInline):
    model = StudentProfile
    # form = StudentProfileValidationForm  <-- (기존에 있다면 유지)
    can_delete = False
    verbose_name_plural = '학생 상세 정보'
    fk_name = 'user'
    autocomplete_fields = ['school']
    readonly_fields = ('attendance_code', 'current_grade_display')

    # [핵심 1] 시간표 필드들은 'Select2(자동완성)'를 끄고 '표준 Select' 사용 강제
    # 이렇게 해야 JavaScript가 설정한 disabled 속성이 화면에 보입니다.
    formfield_overrides = {
        ClassTime: {'widget': Select}, 
    }

    fieldsets = (
        ('기본 정보', {
            'fields': ('branch', 'name', 'school', 'base_year', 'base_grade', 'current_grade_display', 'phone_number', 'attendance_code')
        }),
        ('학부모 연락처 & 알림 설정', {
            'fields': (
                'parent_phone_mom', 
                'parent_phone_dad',
                'notification_recipient',
                'send_attendance_alarm',
                'send_report_alarm',
            )
        }),
        ('수업 및 담당 강사', {
            'description': '⚠️ <b>담당 선생님을 먼저 선택</b>하면, 중복된(1:1) 시간표는 <b>회색으로 비활성화</b> 됩니다.',
            'fields': (
                ('syntax_teacher', 'syntax_class'), 
                ('reading_teacher', 'reading_class'),
                ('extra_class_teacher', 'extra_class_type', 'extra_class'),
            )
        }),
        ('기타', {'fields': ('memo',)}),
    )
    
    class Media:
        js = (
            'admin/js/jquery.init.js',
            'admin/js/class_time_filter.js', # 통합된 JS 파일 하나만 사용
        )

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        # [핵심 2] 시간표 드롭다운 너비 조정 (표준 위젯은 작게 나올 수 있으므로)
        if db_field.name in ['syntax_class', 'reading_class', 'extra_class']:
            kwargs['widget'] = Select(attrs={'style': 'width: 300px;'})

        # 선생님 선택 시 이름+ID 표시
        if db_field.name in ['syntax_teacher', 'reading_teacher', 'extra_class_teacher']:
            class TeacherChoiceField(forms.ModelChoiceField):
                def label_from_instance(self, obj):
                    if hasattr(obj, 'staff_profile') and obj.staff_profile.name:
                        return f"{obj.staff_profile.name} ({obj.username})"
                    return obj.username
            kwargs["form_class"] = TeacherChoiceField
            kwargs["queryset"] = StaffUser.objects.filter(is_staff=True).select_related('staff_profile')

        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    
@admin.register(StudentUser)
class StudentUserAdmin(BaseUserAdmin):
    inlines = (StudentProfileInline,)
    list_display = ('username', 'get_real_name', 'get_branch', 'get_school', 'is_active')
    list_select_related = ('profile', 'profile__school', 'profile__branch')
    search_fields = ('username', 'profile__name', 'profile__school__name')

    def get_real_name(self, obj): return obj.profile.name if hasattr(obj, 'profile') else "-"
    get_real_name.short_description = "이름"

    def get_branch(self, obj): return obj.profile.branch.name if hasattr(obj, 'profile') and obj.profile.branch else "-"
    get_branch.short_description = "지점"

    def get_school(self, obj): return obj.profile.school.name if hasattr(obj, 'profile') and obj.profile.school else "-"
    get_school.short_description = "학교"

    fieldsets = (
        (None, {'fields': ('username', 'password')}),
        ('상태 관리', {'fields': ('is_active',), 'classes': ('collapse',)}),
    )
    
    def get_queryset(self, request):
        return super().get_queryset(request).filter(is_staff=False)

# ==========================================
# 4. 선생님 관리
# ==========================================
class StaffProfileInline(admin.StackedInline):
    model = StaffProfile
    can_delete = False
    verbose_name_plural = '담당 과목 및 직책'
    fk_name = 'user'
    fields = ('name', 'position', 'managed_teachers', 'branch', 'is_syntax_teacher', 'is_reading_teacher')
    filter_horizontal = ('managed_teachers',)
    class Media:
        js = ('admin/js/toggle_vice.js',)

@admin.register(StaffUser)
class StaffUserAdmin(BaseUserAdmin):
    inlines = [StaffProfileInline]
    list_display = ('username', 'get_name', 'get_position', 'is_staff')
    list_filter = ('staff_profile__position', 'staff_profile__branch')

    def save_model(self, request, obj, form, change):
        if not change:  # 새로 만들 때만
            obj.is_staff = True  # <--- "너는 이제부터 선생님(스태프)이야!" 라고 강제 설정
        super().save_model(request, obj, form, change)

    def get_name(self, obj): return obj.staff_profile.name if hasattr(obj, 'staff_profile') else "-"
    get_name.short_description = "성함"

    def get_position(self, obj): return obj.staff_profile.get_position_display() if hasattr(obj, 'staff_profile') else "-"
    get_position.short_description = "직책"

    def get_queryset(self, request):
        return super().get_queryset(request).filter(is_staff=True)

# 기본 User 모델 숨김
admin.site.unregister(User)
admin.site.unregister(Group)

@admin.register(Popup)
class PopupAdmin(admin.ModelAdmin):
    list_display = ('title', 'branch', 'start_date', 'end_date', 'is_active')
    list_filter = ('branch', 'is_active')
    search_fields = ('title', 'content')