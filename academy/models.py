from django.db import models
from django.conf import settings
from django.utils import timezone
import uuid # [NEW]
from django.core.exceptions import ValidationError

# ==========================================
# [1] 출결 및 일정 관리 (Attendance & Schedule)
# ==========================================
class TemporarySchedule(models.Model):
    # 1. 학생
    student = models.ForeignKey(
        'core.StudentProfile', 
        on_delete=models.CASCADE, 
        related_name='temp_schedules',
        verbose_name="학생"
    )
    class SubjectType(models.TextChoices):
        SYNTAX = 'SYNTAX', '구문'
        READING = 'READING', '독해'
        GRAMMAR = 'GRAMMAR', '어법'

    subject = models.CharField(
        max_length=10, 
        choices=SubjectType.choices, 
        default=SubjectType.SYNTAX, 
        verbose_name="보강 과목"
    )

    # 3. "원래 수업 취소 아님(추가 수업)" 체크박스
    is_extra_class = models.BooleanField(
        default=False, 
        verbose_name="추가 보충 여부",
        help_text="체크하면 '기존 수업일(Original Date)'을 입력하지 않아도 됩니다."
    )

    # 4. 기존 수업일
    original_date = models.DateField(null=True, blank=True, verbose_name="기존 수업일 (결석/변경 시)")
    
    # 5. 보강 날짜
    new_date = models.DateField(verbose_name="보강/변경 날짜")

    # 6. 시간표 선택
    target_class = models.ForeignKey(
        'core.ClassTime', 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True, 
        verbose_name="기존 시간표에서 선택"
    )
    
    # 빈칸 허용
    new_start_time = models.TimeField(
        verbose_name="시작 시간", 
        blank=True, 
        null=True
    )
    
    note = models.CharField(max_length=100, blank=True, verbose_name="사유")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "보강 및 일정 변경"
        verbose_name_plural = "보강 및 일정 변경"

    def clean(self):
        if not self.target_class and not self.new_start_time:
            raise ValidationError("기존 시간표를 선택하거나, 시작 시간을 직접 입력해야 합니다.")

    def save(self, *args, **kwargs):
        if self.target_class:
            self.new_start_time = self.target_class.start_time
        super().save(*args, **kwargs)

    def __str__(self):
        return f"[{self.get_subject_display()}] {self.student.name} ({self.new_date})"
    
class Attendance(models.Model):
    """
    일일 출석 기록
    """
    STATUS_CHOICES = [
        ('PRESENT', '✅ 출석'),
        ('LATE', '⚠️ 지각'),
        ('ABSENT', '❌ 결석'),
    ]

    student = models.ForeignKey(
        'core.StudentProfile', 
        on_delete=models.CASCADE, 
        related_name='attendances',
        verbose_name="학생"
    )    

    date = models.DateField(default=timezone.now, verbose_name="날짜")
    
    check_in_time = models.DateTimeField(null=True, blank=True, verbose_name="등원 시간")
    left_at = models.DateTimeField(null=True, blank=True, verbose_name="하원 시간")
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default='PRESENT', verbose_name="상태")
    message_sent = models.BooleanField(default=False, verbose_name="알림 발송 여부")
    
    memo = models.CharField(max_length=50, blank=True, verbose_name="비고")

    class Meta:
        verbose_name = "일일 출석부"
        verbose_name_plural = "일일 출석부"
        unique_together = ('student', 'date')

    def __str__(self):
         return f"[{self.date}] {self.student.name}: {self.get_status_display()}"


# ==========================================
# [2] 수업 일지 및 교재 관리 (Class Log)
# ==========================================

class Textbook(models.Model):
    CATEGORY_CHOICES = [
        ('SYNTAX',  '📘 구문 교재'),
        ('READING', '📙 독해 교재'),
        ('GRAMMAR', '📗 어법 교재'),
        ('LISTENING', '🎧 듣기 교재'),
        ('SCHOOL_EXAM', '🏫 내신 대비'),
    ]

    title = models.CharField(max_length=100, verbose_name="교재명")
    publisher = models.CharField(max_length=50, blank=True, verbose_name="출판사")
    level = models.CharField(max_length=20, blank=True, verbose_name="레벨")
    category = models.CharField(max_length=12, choices=CATEGORY_CHOICES, default='SYNTAX', verbose_name="교재 유형")

    # [NEW] 그래프 그릴 때 '분모'가 됩니다.
    total_units = models.IntegerField(default=0, verbose_name="총 챕터/강 수 (그래프용)")

    # [NEW] OT 강의 포함 여부
    has_ot = models.BooleanField(default=False, verbose_name="OT 강의 여부")

    class Meta:
        verbose_name = "교재"
        verbose_name_plural = "교재"
        ordering = ['category', 'title']

    def __str__(self):
        return f"[{self.get_category_display()}] {self.title}"


class TextbookUnit(models.Model):
    """
    교재 단원별 링크 정보 (플립러닝 과제용)
    """
    textbook = models.ForeignKey(Textbook, on_delete=models.CASCADE, related_name='units', verbose_name="교재")
    unit_number = models.IntegerField(verbose_name="강 번호")
    link_url = models.URLField(blank=True, verbose_name="링크 URL")

    class Meta:
        verbose_name = "교재 단원"
        verbose_name_plural = "교재 단원"
        ordering = ['textbook', 'unit_number']
        unique_together = ('textbook', 'unit_number')

    def __str__(self):
        return f"{self.textbook.title} {self.unit_number}강"


# [중요] ClassLog(부모)가 먼저 와야 합니다!
class ClassLog(models.Model):
    """
    하루 수업 일지 (헤더)
    """
    student = models.ForeignKey(
        'core.StudentProfile', 
        on_delete=models.CASCADE, 
        related_name='class_logs',
        verbose_name="학생"
    )
    subject = models.CharField(
        max_length=20, 
        choices=[('SYNTAX', '구문'), ('READING', '독해'), ('GRAMMAR', '어법')], 
        default='SYNTAX', 
        verbose_name="과목"
    )
    date = models.DateField(verbose_name="수업 날짜")
    teacher = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='written_logs')
    comment = models.TextField(blank=True, verbose_name="선생님 코멘트")
    
    # [NEW] 독해 수업용 복습 테스트 필드 (구문 수업의 단어 테스트와 대응)
    reading_test_type = models.CharField(max_length=50, blank=True, verbose_name="독해 테스트 유형", help_text="예: 빈칸추론, 순서배열")
    reading_test_score = models.CharField(max_length=20, blank=True, verbose_name="독해 테스트 결과", help_text="예: 통과, 재시, 80점")

    # 플립러닝 과제 관련 필드 (기존 유지)
    next_hw_start = models.IntegerField(null=True, blank=True, verbose_name="다음 과제 시작 강")
    next_hw_end = models.IntegerField(null=True, blank=True, verbose_name="다음 과제 끝 강")
    teacher_comment = models.TextField(blank=True, verbose_name="선생님 코멘트 (과제용)")
    created_at = models.DateTimeField(auto_now_add=True)

    hw_vocab_book = models.ForeignKey('vocab.WordBook', on_delete=models.SET_NULL, null=True, blank=True, related_name='hw_logs', verbose_name="과제 단어장")
    hw_vocab_range = models.CharField(max_length=50, blank=True, verbose_name="과제 단어 범위")
    
    hw_main_book = models.ForeignKey(Textbook, on_delete=models.SET_NULL, null=True, blank=True, related_name='hw_logs', verbose_name="과제 주교재")
    hw_main_range = models.CharField(max_length=50, blank=True, verbose_name="과제 진도 범위")

    # [NEW] 과제 마감일 (N-Split 계산 및 일반 과제 마감용)
    hw_due_date = models.DateTimeField(null=True, blank=True, verbose_name="과제 마감일")

    notification_sent_at = models.DateTimeField(null=True, blank=True, verbose_name="알림 발송 시간")
    
    class Meta:
        verbose_name = "수업 일지"
        verbose_name_plural = "수업 일지"
        ordering = ['-date']

    def __str__(self):
        return f"[{self.date}] {self.student.name} {self.get_subject_display()} 수업일지"


# [중요] ClassLogEntry(자식)는 그 다음에 와야 합니다!
class ClassLogEntry(models.Model):
    # Remove the strict choices enforcement on the model level to allow numbers (e.g., "28")
    # We keep the list here just for reference or UI dropdowns for textbooks
    SCORE_CHOICES = [
        ('A', 'A (우수)'),
        ('B', 'B (보통)'),
        ('C', 'C (미흡)'),
        ('F', 'F (재시험)'),
    ]

    class_log = models.ForeignKey(ClassLog, on_delete=models.CASCADE, related_name='entries')
    textbook = models.ForeignKey(Textbook, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="교재")
    wordbook = models.ForeignKey('vocab.WordBook', on_delete=models.SET_NULL, null=True, blank=True, verbose_name="단어장")
    
    progress_range = models.CharField(max_length=20, verbose_name="진도 범위(숫자)")
    
    # [MODIFIED] max_length increased to 10 (to allow "100" or "28/30")
    # removed choices=SCORE_CHOICES to allow arbitrary input
    score = models.CharField(max_length=10, null=True, blank=True, verbose_name="성취도/점수")
    
    def clean(self):
        from django.core.exceptions import ValidationError
        if not self.textbook and not self.wordbook:
            raise ValidationError("교재 또는 단어장 중 하나를 선택해야 합니다.")
        if self.textbook and self.wordbook:
            raise ValidationError("교재와 단어장을 동시에 선택할 수 없습니다.")

    def __str__(self):
        book_name = self.textbook if self.textbook else (self.wordbook if self.wordbook else "미지정")
        return f"{book_name} - {self.progress_range}"

# ==========================================
# [3] 주간 과제 및 인증 관리 (Weekly Assignment)
# ==========================================

class AssignmentTask(models.Model):
    class AssignmentType(models.TextChoices):
        MANUAL = 'MANUAL', '일반 (사진 인증)'
        VOCAB_TEST = 'VOCAB_TEST', '단어 시험 (앱 연동)'

    # 1. 기본 정보
    student = models.ForeignKey(
        'core.StudentProfile', 
        on_delete=models.CASCADE, 
        related_name='assignments',
        verbose_name="학생"
    )
    teacher = models.ForeignKey(
        settings.AUTH_USER_MODEL, 
        on_delete=models.SET_NULL, 
        null=True, 
        related_name='assigned_tasks',
        verbose_name="생성자"
    )
    
    # [NEW] 수업 일지와의 연결 (어느 수업에서 파생된 숙제인지)
    origin_log = models.ForeignKey(
        'ClassLog', 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True,
        related_name='generated_assignments',
        verbose_name="출처 수업일지"
    )

    assignment_type = models.CharField(
        max_length=20, 
        choices=AssignmentType.choices, 
        default=AssignmentType.MANUAL, 
        verbose_name="과제 유형"
    )

    title = models.CharField(max_length=100, verbose_name="과제명")
    description = models.TextField(blank=True, verbose_name="상세 내용")
    due_date = models.DateTimeField(verbose_name="마감일")
    
    # [NEW] 수행 가능 시작일 (자동 계산: due_date - 1일)
    start_date = models.DateTimeField(
        null=True, 
        blank=True, 
        verbose_name="수행 가능 시작일",
        help_text="자동 계산됨. 이 날짜 이전에는 학생이 과제 수행 불가"
    )
    
    # 2. 유형 B (앱 연동) 전용 필드
    related_vocab_book = models.ForeignKey(
        'vocab.WordBook', 
        on_delete=models.SET_NULL, 
        null=True, 
        blank=True,
        verbose_name="대상 단어장 (Type B)"
    )
    vocab_range_start = models.IntegerField(default=0, verbose_name="시작 Day")
    vocab_range_end = models.IntegerField(default=0, verbose_name="종료 Day")

    # [NEW] 유형 A (교재 과제) 전용 필드
    related_textbook = models.ForeignKey(
        'Textbook',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        verbose_name="대상 교재"
    )
    textbook_range = models.CharField(
        max_length=20, 
        blank=True, 
        verbose_name="교재 범위 (예: 1-3)",
        help_text="시작강-끝강 형태로 입력"
    )

    # 3. 상태 관리
    is_completed = models.BooleanField(default=False, verbose_name="완료 여부")
    completed_at = models.DateTimeField(null=True, blank=True, verbose_name="완료 일시")
    
    # [NEW] 누적 범위 여부 (N-Split 리뉴얼)
    is_cumulative = models.BooleanField(default=False, verbose_name="누적 범위 여부", help_text="체크 시 이전 범위도 함께 포함")

    # [NEW] 반려 관련 상태
    is_rejected = models.BooleanField(default=False, verbose_name="반려됨")
    resubmission_deadline = models.DateField(null=True, blank=True, verbose_name="재제출 마감일")
    is_replaced = models.BooleanField(default=False, verbose_name="대체됨")

    class Meta:
        ordering = ['due_date']
        verbose_name = "주간 과제"
        verbose_name_plural = "주간 과제"

    def __str__(self):
        return f"[{self.assignment_type}] {self.student.name}: {self.title}"

class AssignmentSubmission(models.Model):
    task = models.OneToOneField(AssignmentTask, on_delete=models.CASCADE, related_name='submission', verbose_name="관련 과제")
    student = models.ForeignKey('core.StudentProfile', on_delete=models.CASCADE, verbose_name="제출 학생")
    
    image = models.ImageField(upload_to='assignments/%Y/%m/%d/', verbose_name="인증샷")
    submitted_at = models.DateTimeField(auto_now_add=True, verbose_name="제출 시간")
    
    class Status(models.TextChoices):
        PENDING = 'PENDING', '검사 대기'
        APPROVED = 'APPROVED', '승인(완료)'
        REJECTED = 'REJECTED', '반려(재제출)'
        
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.PENDING, verbose_name="상태")
    teacher_comment = models.TextField(blank=True, verbose_name="선생님 피드백")
    reviewed_at = models.DateTimeField(null=True, blank=True, verbose_name="검사 시간")

    class Meta:
        ordering = ['-submitted_at']
        verbose_name = "과제 인증"
        verbose_name_plural = "과제 인증"

class AssignmentSubmissionImage(models.Model):
    submission = models.ForeignKey(
        AssignmentSubmission,
        on_delete=models.CASCADE,
        related_name='images',
        verbose_name="과제 인증",
    )
    image = models.ImageField(upload_to='assignments/%Y/%m/%d/', verbose_name="인증샷")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']
        verbose_name = "과제 인증 이미지"
        verbose_name_plural = "과제 인증 이미지"

# ==========================================
# [4] 성적표 (Web Report Card)
# ==========================================
class StudentReport(models.Model):
    """
    웹 성적표 (Snapshot)
    - 특정 기간 동안의 학습 데이터를 JSON으로 저장하여 박제합니다.
    - 학부모에게 공유되는 UUID 링크를 가집니다.
    """
    student = models.ForeignKey('core.StudentProfile', on_delete=models.CASCADE, related_name='academy_reports', verbose_name="학생")
    teacher = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, verbose_name="발행 선생님")
    
    uuid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    
    title = models.CharField(max_length=100, verbose_name="성적표 제목") # 예: 2024년 1월 학습 리포트
    start_date = models.DateField(verbose_name="조회 시작일")
    end_date = models.DateField(verbose_name="조회 종료일")
    
    # Snapshot Data
    data_snapshot = models.JSONField(verbose_name="데이터 스냅샷", default=dict)
    # {
    #   'attendance': {...},
    #   'vocab': {...},
    #   'assignments': [...],
    #   'mock_exams': [...]
    # }
    
    teacher_comment = models.TextField(blank=True, verbose_name="선생님 총평")
    
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f"[{self.student.name}] {self.title}"

    class Meta:
        verbose_name = "성적표"
        verbose_name_plural = "성적표 관리"
        ordering = ['-created_at']
