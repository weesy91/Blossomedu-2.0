from django.db import models
from django.conf import settings
from django.utils import timezone
from django.contrib.auth.models import User
import datetime

# ==========================================
# 1. 지점(캠퍼스) 관리
# ==========================================
class Branch(models.Model):
    name = models.CharField(max_length=20, verbose_name="지점명")
    def __str__(self): return self.name
    class Meta:
        verbose_name = "지점(캠퍼스)"
        verbose_name_plural = "지점(캠퍼스)"

# ==========================================
# 2. 학교 관리
# ==========================================
class School(models.Model):
    branches = models.ManyToManyField(Branch, related_name='schools', verbose_name="관련 지점", blank=True)
    name = models.CharField(max_length=30, verbose_name="학교명")
    region = models.CharField(max_length=30, verbose_name="지역", blank=True)
    def __str__(self): return self.name
    class Meta:
        verbose_name = "학교"
        verbose_name_plural = "학교"

# ==========================================
# 3. 수업 시간표
# ==========================================
class ClassTime(models.Model):
    branch = models.ForeignKey(Branch, on_delete=models.CASCADE, verbose_name="지점", null=True, blank=True)
    name = models.CharField(max_length=50, verbose_name="수업명 (예: 구문_평일)")
    
    class DayChoices(models.TextChoices):
        MON = 'Mon', '월요일'
        TUE = 'Tue', '화요일'
        WED = 'Wed', '수요일'
        THU = 'Thu', '목요일'
        FRI = 'Fri', '금요일'
        SAT = 'Sat', '토요일'
        SUN = 'Sun', '일요일'
    day = models.CharField(max_length=3, choices=DayChoices.choices, verbose_name="요일")
    start_time = models.TimeField(verbose_name="시작 시간")
    end_time = models.TimeField(verbose_name="종료 시간")

    def __str__(self):
        # 날짜 포맷: 시:분 (예: 16:00)
        start_str = self.start_time.strftime('%H:%M')
        
        # 출력 예시: [월요일] 16:00 (구문)
        return f"[{self.get_day_display()}] {start_str} ({self.name})"

    class Meta:
        verbose_name = "수업 시간표"
        verbose_name_plural = "수업 시간표"

# ==========================================
# [신규] 선생님 프로필 (담당 과목 설정용)
# ==========================================
class StaffProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='staff_profile')
    
    # 소속 지점
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="소속 지점")
    name = models.CharField(max_length=20, null=True, blank=True, verbose_name="선생님 성함")

    # 👇 [추가] 1. 직책 구분 (강사 vs 부원장)
    POSITION_CHOICES = [
        ('TEACHER', '일반 강사'),
        ('VICE', '부원장'),
    ]
    position = models.CharField(max_length=10, choices=POSITION_CHOICES, default='TEACHER', verbose_name="직책")

    # 👇 [추가] 2. 부원장일 경우, 관리할 선생님들 (여러 명 선택 가능)
    # limit_choices_to={'is_staff': True} : 관리자(선생님) 계정만 선택 목록에 뜨게 함
    managed_teachers = models.ManyToManyField(
        settings.AUTH_USER_MODEL, 
        blank=True, 
        related_name='managers',
        limit_choices_to={'is_staff': True},
        verbose_name="[부원장용] 담당 강사 선택"
    )

    # [핵심] 이 선생님이 무슨 수업이 가능한지 체크
    is_syntax_teacher = models.BooleanField(default=False, verbose_name="구문 수업 가능")
    is_reading_teacher = models.BooleanField(default=False, verbose_name="독해 수업 가능")
    
    def __str__(self):
        roles = []
        if self.is_syntax_teacher: roles.append("구문")
        if self.is_reading_teacher: roles.append("독해")
        role_str = "/".join(roles) if roles else "미정"
        branch_name = self.branch.name if self.branch else "지점미정"
        return f"[{branch_name}] {self.user.username} ({role_str})"

# ==========================================
# 4. 학생 프로필 (필터링 강화!)
# ==========================================
class StudentProfile(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='profile')
    branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="소속 지점")

    name = models.CharField(max_length=10, verbose_name="학생 이름")
    school = models.ForeignKey(School, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="학교")
    
    class GradeChoices(models.IntegerChoices):
        E1=1,'초1'; E2=2,'초2'; E3=3,'초3'; E4=4,'초4'; E5=5,'초5'; E6=6,'초6'
        M1=7,'중1'; M2=8,'중2'; M3=9,'중3'; H1=10,'고1'; H2=11,'고2'; H3=12,'고3'; GRAD=13,'졸업/성인'
    base_year = models.IntegerField(verbose_name="기준 연도", default=datetime.date.today().year)
    base_grade = models.IntegerField(choices=GradeChoices.choices, verbose_name="기준 학년", default=7)

    address = models.CharField(max_length=200, verbose_name="주소", blank=True, null=True)
    attendance_code = models.CharField(max_length=4, null=True, blank=True, verbose_name="출석 코드")
    phone_number = models.CharField(max_length=20, blank=True, verbose_name="전화번호")
    parent_phone_mom = models.CharField(max_length=15, verbose_name="어머님 연락처", blank=True, null=True)
    parent_phone_dad = models.CharField(max_length=15, verbose_name="아버님 연락처", blank=True, null=True)
    
    # [수정] 구문 담당쌤 -> 'is_syntax_teacher=True'인 선생님만 보이게 필터링
    syntax_class = models.ForeignKey(
        ClassTime, on_delete=models.SET_NULL, null=True, blank=True,
        verbose_name="구문 시간표", related_name="students_syntax",
        limit_choices_to={'name__contains': '구문'} 
    )
    syntax_teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        verbose_name="구문 담당 선생님", related_name='syntax_students',
        limit_choices_to={'staff_profile__is_syntax_teacher': True}
    )

    # [수정] 독해 담당쌤 -> 'is_reading_teacher=True'인 선생님만 보이게 필터링
    reading_class = models.ForeignKey(
        ClassTime, on_delete=models.SET_NULL, null=True, blank=True,
        verbose_name="독해 시간표", related_name="students_reading",
        limit_choices_to={'name__contains': '독해'}
    )
    reading_teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        verbose_name="독해 담당 선생님", related_name='reading_students',
        limit_choices_to={'staff_profile__is_reading_teacher': True}
    )

    # [신규 추가] 주 3회/보강 등 추가 수업(Extra Class)
    extra_class = models.ForeignKey(
        'ClassTime', on_delete=models.SET_NULL, null=True, blank=True,
        verbose_name="추가 수업 시간", related_name="students_extra"
    )
    extra_class_teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
        verbose_name="추가 수업 담당 선생님", related_name='extra_students'
    )
    extra_class_type = models.CharField(
        max_length=10,
        choices=[('SYNTAX', '구문'), ('READING', '독해')],
        null=True, blank=True,
        verbose_name="추가 수업 종류"
    )

    memo = models.TextField(blank=True, verbose_name="특이사항 메모")
    last_failed_at = models.DateTimeField(null=True, blank=True)
    last_wrong_failed_at = models.DateTimeField(null=True, blank=True)
    
    @property
    def current_grade(self):
        return min(self.base_grade + (timezone.now().year - self.base_year), 13)

    @property
    def extra_class_day(self):
        """추가 수업이 있는 요일을 반환 (예: 'MON')"""
        if self.extra_class:
            return self.extra_class.day
        return None
        
    @property
    def current_grade_display(self):
        return self.GradeChoices(self.current_grade).label

    def save(self, *args, **kwargs):
        if not self.attendance_code and self.phone_number:
            clean_number = self.phone_number.replace('-', '').strip()
            if len(clean_number) >= 4: self.attendance_code = clean_number[-4:]
        super().save(*args, **kwargs)
    
    def __str__(self):
        return f"[{self.branch.name if self.branch else '지점미정'}] {self.name}"
    
    class Meta:
        verbose_name = "학생 프로필"
        verbose_name_plural = "학생 프로필"

# ==========================================
# 5. 선생님 & 학생 계정 관리 (Proxy Models)
# ==========================================
class StaffUser(User):
    class Meta:
        proxy = True 
        app_label = 'auth'
        verbose_name = "선생님 계정"
        verbose_name_plural = "선생님 계정 관리"

class StudentUser(User):
    class Meta:
        proxy = True 
        app_label = 'auth'
        verbose_name = "학생 계정"
        verbose_name_plural = "학생 계정 관리"

