from django import forms
from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin
from django.contrib.auth.models import User, Group 
from django.http import HttpResponse 
from django.db.models import Case, When, IntegerField
from .models import School, StudentProfile, ClassTime, Branch, StaffUser, StudentUser, StaffProfile

# 👇 [NEW] 중복 수업 방지 검증 로직 (여기 추가하세요!)
class StudentProfileValidationForm(forms.ModelForm):
    class Meta:
        model = StudentProfile
        fields = '__all__'

    def clean(self):
        cleaned_data = super().clean()
        instance = self.instance 

        # 독해(READING)는 1:다 수업이므로 중복 검사 제외!
        # 구문과 추가수업만 1:1 체크합니다.
        check_list = [
            ('구문', 'syntax_teacher', 'syntax_class'),
            ('추가', 'extra_class_teacher', 'extra_class'),
        ]

        for subject_name, teacher_field, class_field in check_list:
            teacher = cleaned_data.get(teacher_field)
            class_time = cleaned_data.get(class_field)

            # 선생님과 시간이 둘 다 선택되었을 때만 검사
            if teacher and class_time:
                # 1. "해당 선생님"이 "해당 시간표(ID)"에 수업이 있는지 확인
                # 시간 계산 필요 없음. 그냥 같은 옵션(Slot)을 골랐는지만 보면 됨.
                conflicts = StudentProfile.objects.filter(
                    **{teacher_field: teacher, class_field: class_time}
                )
                
                # 본인 제외
                if instance.pk:
                    conflicts = conflicts.exclude(pk=instance.pk)

                if conflicts.exists():
                    other_student = conflicts.first().name 
                    teacher_name = teacher.staff_profile.name if hasattr(teacher, 'staff_profile') else teacher.username
                    
                    raise forms.ValidationError(
                        f"⛔ [중복 경고] {teacher_name} 선생님은 '{class_time}' 시간에 "
                        f"이미 '{other_student}' 학생의 수업이 있습니다. ({subject_name})"
                    )
        
        return cleaned_data

# ==========================================
# 0. 지점(캠퍼스) 관리
# ==========================================
@admin.register(Branch)
class BranchAdmin(admin.ModelAdmin):
    list_display = ('name',)
    
    def response_add(self, request, obj, post_url_continue=None):
        if "_popup" in request.POST:
            return HttpResponse('''<script>window.close();if(window.opener&&!window.opener.closed){window.opener.location.reload();}</script>''')
        return super().response_add(request, obj, post_url_continue)


# ==========================================
# 1. 학교 관리
# ==========================================
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
        if "_popup" in request.POST:
            return HttpResponse('''<script>window.close();if(window.opener&&!window.opener.closed){window.opener.location.reload();}</script>''')
        return super().response_add(request, obj, post_url_continue)


# ==========================================
# 2. 수업 시간표 관리
# ==========================================
@admin.register(ClassTime)
class ClassTimeAdmin(admin.ModelAdmin):
    list_display = ('__str__', 'branch', 'day', 'start_time', 'end_time')
    list_filter = ('branch', 'day')
    search_fields = ('day', 'start_time', 'name')
    
    def get_queryset(self, request):
        # 요일을 월요일부터 일요일 순서로 정렬
        day_order = Case(
            When(day='Mon', then=0),  # 월요일
            When(day='Tue', then=1),  # 화요일
            When(day='Wed', then=2),  # 수요일
            When(day='Thu', then=3),  # 목요일
            When(day='Fri', then=4),  # 금요일
            When(day='Sat', then=5),  # 토요일
            When(day='Sun', then=6),  # 일요일
            output_field=IntegerField(),
        )
        qs = super().get_queryset(request)
        return qs.annotate(day_order=day_order).order_by('branch', 'day_order', 'start_time')


# ==========================================
# 3. 사용자(Users) 메뉴용 인라인 (학생용)
# ==========================================
class StudentProfileInline(admin.StackedInline):
    model = StudentProfile
    form = StudentProfileValidationForm # 안전장치 연결
    can_delete = False
    verbose_name_plural = '학생 상세 정보 입력'
    fk_name = 'user'
    
    readonly_fields = ('attendance_code', 'current_grade_display')
    
    fieldsets = (
        ('기본 정보', {
            'fields': ('branch', 'name', 'school', 'base_year', 'base_grade', 'current_grade_display', 'phone_number', 'attendance_code')
        }),
        ('수업 및 담당 강사', {
            'description': '⚠️ 선생님을 먼저 선택하면, 이미 마감된 시간은 비활성화(회색) 처리됩니다.',
            'fields': (
                ('syntax_teacher', 'syntax_class'), 
                ('reading_teacher', 'reading_class'),
                ('extra_class_teacher', 'extra_class_type', 'extra_class', ),
            )
        }),
        ('부모님 연락처', {
            'fields': ('parent_phone_dad', 'parent_phone_mom')
        }),
        ('기타', {
            'fields': ('memo',)
        }),
    )
    
    # 👇 [수정됨] 기존 파일(extra_class_filter.js)도 꼭 챙겨야 합니다!
    class Media:
        js = (
            'admin/js/extra_class_filter.js',      # 기존 기능 유지
            'admin/js/jquery.init.js',             # jQuery 로드
            'admin/js/custom_schedule_filter.js',
            'admin/js/class_time_filter.js',  # 새로 만든 마감 기능
        )

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        # ... (이 아래 내용은 아까와 동일하므로 생략하지 않고 그대로 두시면 됩니다) ...
        day_order = Case(
            When(day='Mon', then=0), When(day='Tue', then=1), When(day='Wed', then=2),
            When(day='Thu', then=3), When(day='Fri', then=4), When(day='Sat', then=5),
            When(day='Sun', then=6), output_field=IntegerField(),
        )
        
        if db_field.name == "syntax_class":
            kwargs["queryset"] = ClassTime.objects.filter(name__contains='구문').annotate(day_order=day_order).order_by('day_order', 'start_time')
        elif db_field.name == "reading_class":
            kwargs["queryset"] = ClassTime.objects.filter(name__contains='독해').annotate(day_order=day_order).order_by('day_order', 'start_time')
        elif db_field.name == "extra_class":
            kwargs["queryset"] = ClassTime.objects.annotate(day_order=day_order).order_by('day_order', 'start_time', 'name')

        if db_field.name in ['syntax_teacher', 'reading_teacher', 'extra_class_teacher']:
            class TeacherChoiceField(forms.ModelChoiceField):
                def label_from_instance(self, obj):
                    if hasattr(obj, 'staff_profile') and obj.staff_profile.name:
                        return f"{obj.staff_profile.name} ({obj.username})"
                    return obj.username
            kwargs["form_class"] = TeacherChoiceField
            kwargs["queryset"] = StaffUser.objects.filter(is_staff=True).select_related('staff_profile')

        return super().formfield_for_foreignkey(db_field, request, **kwargs)
    
# ==========================================
# 4. 학생 계정 관리 (StudentUserAdmin)
# ==========================================
@admin.register(StudentUser)
class StudentUserAdmin(BaseUserAdmin):
    inlines = (StudentProfileInline,)

    list_display = ('username', 'get_real_name', 'get_branch', 'get_school', 'is_active')
    list_select_related = ('profile', 'profile__school', 'profile__branch')

    def get_real_name(self, obj):
        return obj.profile.name if hasattr(obj, 'profile') else "-"
    get_real_name.short_description = "학생 이름"

    def get_branch(self, obj):
        return obj.profile.branch.name if hasattr(obj, 'profile') and obj.profile.branch else "-"
    get_branch.short_description = "지점"

    def get_school(self, obj):
        return obj.profile.school.name if hasattr(obj, 'profile') and obj.profile.school else "-"
    get_school.short_description = "학교"

    search_fields = ('username', 'profile__name', 'profile__school__name')

    # [수정] 여기가 핵심입니다! 불필요한 필드들을 싹 숨겼습니다.
    fieldsets = (
        (None, {'fields': ('username', 'password')}),
        # 개인정보, 권한, 중요 날짜 섹션은 아예 제거했습니다.
        # 혹시 계정 정지(퇴원)가 필요할 수 있으니 '활성 상태'만 접힌 메뉴로 남겨둡니다.
        ('계정 상태 (클릭하여 열기)', {
            'fields': ('is_active',),
            'classes': ('collapse',)
        }),
    )

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.filter(is_staff=False) 

# 기존 User 및 Group 메뉴 숨김
admin.site.unregister(User)
admin.site.unregister(Group)


# ==========================================
# [신규] 선생님 프로필 인라인 (담당 과목 체크박스)
# ==========================================
class StaffProfileInline(admin.StackedInline):
    model = StaffProfile
    can_delete = False
    verbose_name_plural = '담당 과목 설정'
    fk_name = 'user'
    # 👇 [수정] fields 목록에 새로 만든 2개를 추가해주세요.
    fields = ('name', 'position', 'managed_teachers', 'branch', 'is_syntax_teacher', 'is_reading_teacher')
    
    # 'managed_teachers' 선택창을 예쁘게(좌우 이동 UI) 보여주는 옵션
    filter_horizontal = ('managed_teachers',)
    class Media:
        js = ('admin/js/toggle_vice.js',)



# ==========================================
# 5. 선생님 계정 관리 (StaffUserAdmin)
# ==========================================
@admin.register(StaffUser)
class StaffUserAdmin(BaseUserAdmin):
    inlines = [StaffProfileInline] 
    
    list_display = ('username', 'get_roles', 'email', 'is_staff', 'last_login')
    list_filter = ('is_staff', 'is_superuser', 'staff_profile__is_syntax_teacher', 'staff_profile__is_reading_teacher')
    search_fields = ('username', 'email')

    # 선생님 관리 화면도 깔끔하게 정리 (필요시 권한 설정 등은 보이게 유지)
    fieldsets = (
        (None, {'fields': ('username', 'password')}),
        ('개인 정보', {'fields': ('email',)}),
        ('권한', {'fields': ('is_active', 'is_staff', 'is_superuser')}),
    )

    def get_roles(self, obj):
        if hasattr(obj, 'staff_profile'):
            return str(obj.staff_profile).split('(')[-1].replace(')', '')
        return "-"
    get_roles.short_description = "담당 과목"

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        return qs.filter(is_staff=True)

    def save_model(self, request, obj, form, change):
        if not change: 
            obj.is_staff = True 
        super().save_model(request, obj, form, change)


# ==========================================
# 6. 학생 프로필 (Student Profiles) 메뉴 설정
# ==========================================
@admin.register(StudentProfile)
class StudentProfileAdmin(admin.ModelAdmin):
    search_fields = ('name', 'school__name', 'phone_number')
    
    list_display = ('name', 'branch', 'syntax_teacher', 'reading_teacher', 'get_current_grade_str')
    
    list_filter = ('branch', 'syntax_teacher', 'reading_teacher', 'base_grade')

    fieldsets = (
        ('기본 정보', {
            'fields': ('user', 'branch', 'name', 'school', 'phone_number', 'attendance_code')
        }),
        ('수업 및 담당 강사', {
            'description': '학생이 듣는 수업 시간과, 해당 과목을 가르치는 1:1 담당 선생님을 지정하세요.',
            'fields': (
                ('syntax_class', 'syntax_teacher'), 
                ('reading_class', 'reading_teacher'),
                # 👇 [여기!] 추가 수업 관련 필드 3개를 한 줄에 추가했습니다.
                ('extra_class', 'extra_class_teacher', 'extra_class_type'),
            )
        }),
        ('부모님 연락처', {
            'fields': ('parent_phone_dad', 'parent_phone_mom')
        }),
        ('기타', {
            'fields': ('base_year', 'base_grade', 'current_grade_display', 'memo')
        }),
    )

    readonly_fields = ('attendance_code', 'current_grade_display')

    def get_current_grade_str(self, obj):
        return obj.current_grade_display
    get_current_grade_str.short_description = "학년"

    def get_model_perms(self, request):
        if request.user.is_superuser:
            return super().get_model_perms(request)
        return {}