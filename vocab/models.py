import csv
from io import TextIOWrapper
from django.db import models
from django.conf import settings
from django.db import transaction
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from django.utils import timezone
from core.models import Branch, School # School import added 
from datetime import timedelta

# ==========================================
# [1] 단어장 관리 (WordBook & Word)
# ==========================================

class Publisher(models.Model):
    name = models.CharField(max_length=50, unique=True, verbose_name="출판사명")

    def __str__(self):
        return self.name

# 1-1. [NEW] 마스터 단어 DB (Global Unique)
class MasterWord(models.Model):
    """
    모든 영단어의 유니크 저장소 (Apple은 딱 하나만 존재)
    """
    text = models.CharField(max_length=100, unique=True, db_index=True, verbose_name="영단어")
    created_at = models.DateTimeField(auto_now_add=True)

    def __str__(self):
        return self.text

class WordMeaning(models.Model):
    POS_CHOICES = (
        ('n', '명사'),
        ('v', '동사'),
        ('adj', '형용사'),
        ('adv', '부사'),
        ('pron', '대명사'),
        ('prep', '전치사'),
        ('conj', '접속사'),
        ('interj', '감탄사'),
    )
    """
    하나의 단어가 가질 수 있는 다양한 뜻 (사과, 아이폰, 능금...)
    """
    master_word = models.ForeignKey(MasterWord, on_delete=models.CASCADE, related_name='meanings')
    meaning = models.CharField(max_length=100, verbose_name="뜻")
    pos = models.CharField(max_length=10, choices=POS_CHOICES, default='n', verbose_name="품사")
    source = models.CharField(max_length=50, blank=True, verbose_name="출처/뉘앙스") # 예: '일반', '의학', '법률'

    class Meta:
        unique_together = ('master_word', 'meaning')

    def __str__(self):
        return f"{self.master_word.text}: {self.meaning}"


class WordBook(models.Model):
    publisher = models.ForeignKey(Publisher, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="출판사")
    title = models.CharField(max_length=100, verbose_name="단어장 제목")
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, verbose_name="등록자")
    created_at = models.DateTimeField(auto_now_add=True)
    csv_file = models.FileField(upload_to='csvs/', blank=True, null=True, verbose_name="CSV 파일")
    cover_image = models.FileField(upload_to='covers/', blank=True, null=True, verbose_name="표지/배경 이미지")

    # [NEW] School-Specific Visibility
    target_branch = models.ForeignKey(Branch, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="대상 지점 (본사=NULL)")
    target_school = models.ForeignKey(School, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="대상 학교")
    target_grade = models.IntegerField(null=True, blank=True, verbose_name="대상 학년 (전체=NULL)")

    def __str__(self):
        return self.title

    class Meta:
        verbose_name = "단어장"
        verbose_name_plural = "단어장"

    def _infer_pos(self, meaning):
        """한글 뜻을 분석하여 품사를 추론하는 휴리스틱 함수 (8품사 지원)"""
        m = meaning.strip()
        # 1. 동사 (~다)
        if m.endswith('다'): return 'v'
        # 2. 형용사 (~ㄴ, ~은, ~는, ~한, ~적인, ~의)
        if any(m.endswith(suffix) for suffix in ['ㄴ', '은', '는', '한', '적인', '의']): return 'adj'
        # 3. 부사 (~게, ~히, ~으로)
        if any(m.endswith(suffix) for suffix in ['게', '히', '으로']): return 'adv'
        # 4. 그 외 (명사, 대명사 등) -> 기본값 'n'
        # * 전치사/접속사/감탄사는 자동 추론이 어려워 기본값 후 수동 수정 권장
        return 'n'

    # [핵심] CSV 파일 자동 등록 로직 (Master DB 연동 버전)
    @transaction.atomic
    def save(self, *args, **kwargs):
        # [NEW] Auto-set Branch
        if not self.pk and not self.target_branch and hasattr(self, 'uploaded_by'):
             try:
                 # Check if uploader is staff and has branch
                 if hasattr(self.uploaded_by, 'staff_profile') and self.uploaded_by.staff_profile.branch:
                     self.target_branch = self.uploaded_by.staff_profile.branch
             except Exception:
                 pass # Skip if user not ready or profile missing
        
        super().save(*args, **kwargs)
        if not self.csv_file or self.words.exists():
            return
        
        print(f"--- [DEBUG] 단어장 '{self.title}' 파일 분석 및 마스터 DB 연동 시작 ---")
        file_obj = self.csv_file.file
        file_obj.seek(0)
        
        # 인코딩 처리
        try:
            decoded_file = TextIOWrapper(file_obj, encoding='utf-8-sig')
            reader = csv.reader(decoded_file)
            rows = list(reader)
        except UnicodeDecodeError:
            file_obj.seek(0)
            decoded_file = TextIOWrapper(file_obj, encoding='cp949')
            reader = csv.reader(decoded_file)
            rows = list(reader)

        entries_to_create = []

        for i, row in enumerate(rows):
            if len(row) < 2: continue # At least English/Korean needed
            
            day_str = row[0].strip() if len(row) > 0 else "1"
            eng_val = row[1].strip() if len(row) > 1 else ""
            kor_val = row[2].strip() if len(row) > 2 else ""
            example_val = row[3].strip() if len(row) > 3 else ""
            
            if not eng_val or not kor_val: continue
            
            # Header Check (Robuster)
            if eng_val.lower() in ['word', 'english', '영어', '단어', 'eng', 'words']: continue
            if kor_val.lower() in ['meaning', 'korean', '뜻', '의미', 'kor', 'meanings']: continue 
            
            try: num_val = int(day_str)
            except ValueError: num_val = 1 

            # 1. MasterWord 확인 및 생성 (없으면 만듦)
            master_word, _ = MasterWord.objects.get_or_create(text=eng_val)

            # 2. Meaning 추가 (없으면 만듦)
            # 쉼표로 구분된 뜻이 들어올 경우 쪼개서 넣는 로직도 가능하나, 일단 통으로 저장하거나 추후 정제
            from . import services
            entries = services.parse_meaning_tokens(kor_val)
            for entry in entries:
                wm, created = WordMeaning.objects.get_or_create(
                    master_word=master_word,
                    meaning=entry['meaning'],
                    defaults={'pos': entry['pos']},
                )
                if entry['manual'] and wm.pos != entry['pos']:
                    wm.pos = entry['pos']
                    wm.save(update_fields=['pos'])

            # 3. 책에 연결 (Entry 생성)
            entries_to_create.append(Word(
                book=self, 
                master_word=master_word, # [NEW] 링크 연결
                english=eng_val,  # 여전히 검색 편의를 위해 유지 (또는 제거 가능)
                korean=kor_val, 
                number=num_val, 
                example_sentence=example_val
            ))

        if entries_to_create:
            Word.objects.bulk_create(entries_to_create)
            print(f"--- [성공] {len(entries_to_create)}개 단어 등록 및 마스터 DB 연동 완료 ---")

class Word(models.Model):
    """
    [WordBookEntry] 역할
    특정 책의 몇 페이지(Day)에 어떤 단어(MasterWord)가 쓰였는지 매핑
    """
    book = models.ForeignKey(WordBook, on_delete=models.CASCADE, related_name='words')
    master_word = models.ForeignKey(MasterWord, on_delete=models.CASCADE, null=True, blank=True, related_name='book_entries', verbose_name="마스터 단어 링크")
    
    number = models.IntegerField(default=1, verbose_name="Day/Unit")
    english = models.CharField(max_length=100) # 캐싱/검색용으로 유지 (MasterWord.text와 동일)
    korean = models.CharField(max_length=100) # 이 책에서 채택한 대표 뜻
    example_sentence = models.TextField(null=True, blank=True)

    class Meta:
        # unique_together = ('book', 'english') # REMOVED: Allow duplicates (polysemy/review)
        ordering = ['number', 'id']

    def __str__(self):
        return f"{self.english} ({self.korean})"


# ==========================================
# [2] 시험 결과 관리 (Test Result)
# ==========================================

# 2-1. 도전 모드 결과 (일반 시험)
class TestResult(models.Model):
    student = models.ForeignKey(
        'core.StudentProfile', 
        on_delete=models.CASCADE, 
        related_name='test_results',
        verbose_name="학생"
    )
    book = models.ForeignKey(WordBook, on_delete=models.CASCADE, verbose_name="시험 본 책")
    assignment_id = models.CharField(max_length=50, blank=True, null=True, verbose_name="과제 ID")
    score = models.IntegerField(default=0, verbose_name="점수")
    total_count = models.IntegerField(default=30)
    wrong_count = models.IntegerField(default=0)
    test_range = models.CharField(max_length=50, blank=True, verbose_name="시험 범위")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="응시 일시")
    
    class Meta:
        verbose_name = "도전모드 결과"
        verbose_name_plural = "도전모드 결과"

    def __str__(self):
        # self.student.profile.name -> self.student.name 으로 단축됨
        return f"[{self.created_at.date()}] {self.student.name} - {self.score}점"

class TestResultDetail(models.Model):
    result = models.ForeignKey(TestResult, on_delete=models.CASCADE, related_name='details')
    word_question = models.CharField(max_length=100)
    student_answer = models.CharField(max_length=100)
    correct_answer = models.CharField(max_length=100)
    is_correct = models.BooleanField(default=False)
    is_correction_requested = models.BooleanField(default=False, verbose_name="정답 정정 요청")
    is_resolved = models.BooleanField(default=False, verbose_name="처리 완료")
    question_pos = models.CharField(max_length=10, blank=True, null=True, verbose_name="문제 품사")

    def __str__(self):
        return f"{self.word_question} ({'O' if self.is_correct else 'X'})"


# 2-2. 월말 평가 결과
class MonthlyTestResult(models.Model):
    student = models.ForeignKey(
        'core.StudentProfile', 
        on_delete=models.CASCADE, 
        related_name='monthly_results'
    )
    book = models.ForeignKey(WordBook, on_delete=models.CASCADE)
    score = models.IntegerField(default=0)
    total_questions = models.IntegerField(default=100)
    test_range = models.CharField(max_length=50, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "월말평가 결과"
        verbose_name_plural = "월말평가 결과"

class MonthlyTestResultDetail(models.Model):
    result = models.ForeignKey(MonthlyTestResult, on_delete=models.CASCADE, related_name='details')
    word_question = models.CharField(max_length=100)
    student_answer = models.CharField(max_length=100)
    correct_answer = models.CharField(max_length=100)
    is_correct = models.BooleanField(default=False)
    is_correction_requested = models.BooleanField(default=False)
    is_resolved = models.BooleanField(default=False)


# ==========================================
# [3] 자동 채점 로직 (Signal)
# ==========================================
# 정답 정정 요청을 선생님이 수락(is_correct=True로 변경)하면, 점수도 자동으로 오르게 합니다.

@receiver(post_save, sender=TestResultDetail)
def update_score_on_change(sender, instance, **kwargs):
    result = instance.result
    # 현재 맞은 개수 다시 세기
    real_score = result.details.filter(is_correct=True).count()
    result.score = real_score
    result.wrong_count = result.total_count - real_score
    result.save()


# ==========================================
# [4] 기록 제거시 3분 쿨타임 제거
# ==========================================
@receiver(post_delete, sender=TestResult)
def auto_reset_cooldown(sender, instance, **kwargs):
    # instance.student가 이제 바로 Profile 객체입니다.
    profile = instance.student 
    
    # 더 이상 hasattr 체크나 profile 접근이 필요 없습니다.
    # if not hasattr(student, 'profile'): return (삭제)
    
    now = timezone.now()
    three_mins_ago = now - timedelta(minutes=3)

    # 쿼리 시 student=profile 로 변경
    recent_challenge_fails = TestResult.objects.filter(
        student=profile,
        score__lt=27,
        created_at__gte=three_mins_ago
    ).exclude(test_range="오답집중")

    if not recent_challenge_fails.exists():
        profile.last_failed_at = None

    recent_wrong_fails = TestResult.objects.filter(
        student=profile,
        score__lt=27,
        created_at__gte=five_mins_ago,
        test_range="오답집중"
    )

    if not recent_wrong_fails.exists():
        profile.last_wrong_failed_at = None

    profile.save()

class PersonalWrongWord(models.Model):
    """
    학생이 직접 검색해서 오답 노트에 추가한 단어 (Global MasterWord 기준)
    """
    student = models.ForeignKey('core.StudentProfile', on_delete=models.CASCADE, related_name='personal_wrong_words')
    
    # [NEW] MasterWord로 변경 (모든 책 통합 오답)
    master_word = models.ForeignKey(MasterWord, on_delete=models.CASCADE, null=True, verbose_name="마스터 단어")
    
    # Legacy Support (기존 데이터 호환을 위해 유지하되, 점차 master_word로 마이그레이션)
    word = models.ForeignKey(Word, on_delete=models.SET_NULL, null=True, blank=True) 

    created_at = models.DateTimeField(auto_now_add=True)
    success_count = models.IntegerField(default=0)  # [3-Strike Rule] 3번 연속 정답 시 졸업
    last_correct_at = models.DateTimeField(null=True, blank=True) # 마지막 정답 시간 (쿨타임용)
    
    class Meta:
        verbose_name = "학생 추가 오답"
        verbose_name_plural = "학생 추가 오답"
        unique_together = ('student', 'master_word') # 중복 추가 방지 (MasterWord 기준)

    def __str__(self):
        if self.master_word:
            return f"{self.student.name} - {self.master_word.text} (stack: {self.success_count})"
        return f"{self.student.name} - Legacy"
    
class RankingEvent(models.Model):
    title = models.CharField(max_length=100, verbose_name="이벤트 타이틀", help_text="예: 🌞 여름방학 능률보카 격파왕")
    target_book = models.ForeignKey(WordBook, on_delete=models.CASCADE, verbose_name="이벤트 대상 단어장")
    
    # 👇 [추가] 지점 선택 필드 (비워두면 전체 공개)
    branch = models.ForeignKey(
        Branch, 
        on_delete=models.CASCADE, 
        null=True, 
        blank=True, 
        verbose_name="진행 지점 (비워두면 전체)"
    )
    
    start_date = models.DateField(verbose_name="시작일")
    end_date = models.DateField(verbose_name="종료일")
    is_active = models.BooleanField(default=True, verbose_name="현재 진행 중")

    class Meta:
        verbose_name = "🏆 랭킹 이벤트 설정"
        verbose_name_plural = "🏆 랭킹 이벤트 설정"

    def __str__(self):
        # 관리자 페이지에서 알아보기 쉽게 표시
        branch_name = self.branch.name if self.branch else "전체 지점"
        return f"[{branch_name}] {self.title}"

# ==========================================
# [NEW] 개인 단어장 (My Books)
# ==========================================
class PersonalWordBook(models.Model):
    """
    학생이 '내 단어장'으로 추가한 교재 목록
    """
    student = models.ForeignKey('core.StudentProfile', on_delete=models.CASCADE, related_name='my_books')
    book = models.ForeignKey(WordBook, on_delete=models.CASCADE, related_name='subscribers')
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        unique_together = ('student', 'book')
        verbose_name = "나의 단어장"
        verbose_name_plural = "나의 단어장"

    def __str__(self):
        return f"{self.student.name} - {self.book.title}"
