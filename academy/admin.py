from django.contrib import admin
from django.http import HttpResponse
from django import forms
from django.contrib.auth import get_user_model
from .models import TemporarySchedule, Attendance, Textbook, TextbookUnit, ClassLog, ClassLogEntry

User = get_user_model()

# ==========================================
# [공통 함수] 팝업 강제 종료 및 부모창 새로고침
# ==========================================
def force_close_popup(request, obj, post_url_continue=None):
    if "_popup" in request.POST:
        return HttpResponse('<script>window.close(); if(window.opener) window.opener.location.reload();</script>')
    return None 

# ==========================================
# [1] 출석 관리 (Attendance)
# ==========================================
@admin.register(Attendance)
class AttendanceAdmin(admin.ModelAdmin):
    # 목록에 보여줄 항목들
    list_display = ('date', 'get_student_name', 'status', 'check_in_time', 'message_sent')
    # 필터 기능
    list_filter = ('date', 'status', 'message_sent')
    # 정렬 (최신순, 등원시간순)
    ordering = ('-date', '-check_in_time')

    # 학생 이름 가져오기 (프로필 연결)
    def get_student_name(self, obj):
        # 안전하게 프로필 이름 가져오기
        return obj.student.profile.name if hasattr(obj.student, 'profile') else obj.student.username
    get_student_name.short_description = "학생 이름"

    # 팝업 저장 시 강제 닫기 적용
    def response_add(self, request, obj, post_url_continue=None):
        return force_close_popup(request, obj, post_url_continue) or \
               super().response_add(request, obj, post_url_continue)

# ==========================================
# [2] 보강/일정 관리 (TemporarySchedule)
# ==========================================
@admin.register(TemporarySchedule)
class TemporaryScheduleAdmin(admin.ModelAdmin):
    # 1. 목록 화면 (여기선 시간이 보여야 확인이 되니 남겨둡니다)
    list_display = ('student', 'get_subject_display', 'is_extra_class', 'original_date', 'new_date', 'new_start_time')
    
    # 2. 입력 화면 설정 (new_start_time 제거!)
    fields = (
        'student', 
        'subject', 
        'is_extra_class', 
        'original_date', 
        'new_date', 
        'target_class',     # 이제 이것만 선택하면 시간이 자동 저장됩니다.
        # 'new_start_time', -> 삭제함 (직접 입력 불가)
        'note'
    )

    # 3. 학생 검색 기능
    autocomplete_fields = ['student']

    # 4. 자바스크립트 연결
    class Media:
        js = ('admin/js/schedule_filter.js',)

    # 5. 드롭다운 필터링
    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "target_class":
            from core.models import ClassTime
            kwargs["queryset"] = ClassTime.objects.order_by('day', 'start_time')
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    # 과목명 한글 표시
    def get_subject_display(self, obj):
        return obj.get_subject_display()
    get_subject_display.short_description = "과목"

    # 팝업 닫기 처리
    def response_add(self, request, obj, post_url_continue=None):
        return force_close_popup(request, obj, post_url_continue) or \
               super().response_add(request, obj, post_url_continue)
    
# ==========================================
# [3] 교재 관리 (Textbook)
# ==========================================
class TextbookUnitInline(admin.TabularInline):
    model = TextbookUnit
    extra = 1
    fields = ('unit_number', 'link_url')
    verbose_name = "단원 링크"
    verbose_name_plural = "단원 링크"

@admin.register(Textbook)
class TextbookAdmin(admin.ModelAdmin):
    list_display = ('title', 'category', 'total_units', 'publisher')
    list_filter = ('category', 'publisher')
    search_fields = ('title', 'publisher')
    ordering = ('category', 'title')
    inlines = [TextbookUnitInline]
    
    def response_add(self, request, obj, post_url_continue=None):
        return force_close_popup(request, obj, post_url_continue) or \
               super().response_add(request, obj, post_url_continue)
    
# ==========================================
# [4] 수업 일지 (ClassLog & Entry)
# ==========================================
# 일지 안에 들어갈 상세 내용 (Inline)
class ClassLogEntryInline(admin.TabularInline):
    model = ClassLogEntry
    extra = 1
    fields = ('textbook', 'wordbook', 'progress_range', 'score')
    verbose_name = "수업 진도 항목"
    verbose_name_plural = "수업 진도 항목"

class StudentChoiceField(forms.ModelChoiceField):
    """학생 이름과 학교명을 표시하는 커스텀 필드"""
    def label_from_instance(self, obj):
        """드롭다운에 학생 이름과 학교명 표시"""
        if hasattr(obj, 'profile'):
            profile = obj.profile
            school_name = profile.school.name if profile.school else "학교 미정"
            return f"{profile.name} ({school_name})"
        return obj.username

class ClassLogAdminForm(forms.ModelForm):
    """ClassLog Admin Form - Student 필드 커스터마이징"""
    student = StudentChoiceField(
        queryset=User.objects.filter(profile__isnull=False).select_related('profile', 'profile__school'),
        label='학생',
        required=True
    )
    
    class Meta:
        model = ClassLog
        fields = '__all__'

@admin.register(ClassLog)
class ClassLogAdmin(admin.ModelAdmin):
    form = ClassLogAdminForm
    list_display = ('date', 'get_student_display', 'get_teacher_name', 'created_at')
    list_filter = ('date', 'created_at')
    search_fields = ('student__username', 'student__profile__name', 'comment')
    ordering = ('-date', '-created_at')
    inlines = [ClassLogEntryInline]  # 상세 내용을 같은 페이지에서 입력
    
    fieldsets = (
        ('기본 정보', {
            'fields': ('student', 'date', 'teacher', 'comment')
        }),
    )

    def get_student_display(self, obj):
        """학생 이름과 학교명을 표시"""
        if hasattr(obj.student, 'profile'):
            profile = obj.student.profile
            school_name = profile.school.name if profile.school else "학교 미정"
            return f"{profile.name} ({school_name})"
        return obj.student.username
    get_student_display.short_description = "학생"
    
    def get_teacher_name(self, obj):
        if obj.teacher:
            return obj.teacher.profile.name if hasattr(obj.teacher, 'profile') else obj.teacher.username
        return "-"
    get_teacher_name.short_description = "선생님"

    def response_add(self, request, obj, post_url_continue=None):
        return force_close_popup(request, obj, post_url_continue) or \
               super().response_add(request, obj, post_url_continue)