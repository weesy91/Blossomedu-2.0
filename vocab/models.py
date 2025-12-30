import csv
from io import TextIOWrapper
from django.db import models
from django.conf import settings
from django.db import transaction
from django.db.models.signals import post_save, post_delete
from django.dispatch import receiver
from django.utils import timezone
from datetime import timedelta

# ==========================================
# [1] 단어장 관리 (WordBook & Word)
# ==========================================

class Publisher(models.Model):
    name = models.CharField(max_length=50, unique=True, verbose_name="출판사명")

    def __str__(self):
        return self.name

class WordBook(models.Model):
    publisher = models.ForeignKey(Publisher, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="출판사")
    title = models.CharField(max_length=100, verbose_name="단어장 제목")
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, verbose_name="등록자")
    created_at = models.DateTimeField(auto_now_add=True)
    csv_file = models.FileField(upload_to='csvs/', blank=True, null=True, verbose_name="CSV 파일")

    def __str__(self):
        return self.title

    class Meta:
        verbose_name = "단어장"
        verbose_name_plural = "단어장"

    # [핵심] CSV 파일 자동 등록 로직
    @transaction.atomic
    def save(self, *args, **kwargs):
        super().save(*args, **kwargs)
        if not self.csv_file or self.words.exists():
            return
        
        print(f"--- [DEBUG] 단어장 '{self.title}' 파일 분석 시작 ---")
        file_obj = self.csv_file.file
        file_obj.seek(0)
        
        # 인코딩 처리 (utf-8-sig 또는 cp949)
        try:
            decoded_file = TextIOWrapper(file_obj, encoding='utf-8-sig')
            reader = csv.reader(decoded_file)
            rows = list(reader)
        except UnicodeDecodeError:
            file_obj.seek(0)
            decoded_file = TextIOWrapper(file_obj, encoding='cp949')
            reader = csv.reader(decoded_file)
            rows = list(reader)

        unique_words = {}
        for i, row in enumerate(rows):
            if i == 0 or len(row) < 3: continue # 헤더거나 데이터 부족하면 패스
            
            day_str = row[0].strip()
            eng_val = row[1].strip()
            kor_val = row[2].strip()
            example_val = row[3].strip() if len(row) > 3 else ""
            
            if not eng_val or not kor_val: continue
            if eng_val.lower() in ['word', 'english', '영어']: continue 
            
            try: num_val = int(day_str)
            except ValueError: num_val = 1 

            unique_words[eng_val] = Word(
                book=self, 
                english=eng_val, 
                korean=kor_val, 
                number=num_val, 
                example_sentence=example_val
            )

        if unique_words:
            Word.objects.bulk_create(unique_words.values())
            print(f"--- [성공] {len(unique_words)}개 단어 등록 완료 ---")

class Word(models.Model):
    book = models.ForeignKey(WordBook, on_delete=models.CASCADE, related_name='words')
    number = models.IntegerField(default=1, verbose_name="Day/Unit")
    english = models.CharField(max_length=100)
    korean = models.CharField(max_length=100)
    example_sentence = models.TextField(null=True, blank=True)

    class Meta:
        unique_together = ('book', 'english')
        ordering = ['number', 'id']

    def __str__(self):
        return f"{self.english} ({self.korean})"


# ==========================================
# [2] 시험 결과 관리 (Test Result)
# ==========================================

# 2-1. 도전 모드 결과 (일반 시험)
class TestResult(models.Model):
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='test_results')
    book = models.ForeignKey(WordBook, on_delete=models.CASCADE, verbose_name="시험 본 책")
    score = models.IntegerField(default=0, verbose_name="점수")
    total_count = models.IntegerField(default=30)
    wrong_count = models.IntegerField(default=0)
    test_range = models.CharField(max_length=50, blank=True, verbose_name="시험 범위")
    created_at = models.DateTimeField(auto_now_add=True, verbose_name="응시 일시")
    
    class Meta:
        verbose_name = "도전모드 결과"
        verbose_name_plural = "도전모드 결과"

    def __str__(self):
        return f"[{self.created_at.date()}] {self.student.profile.name} - {self.score}점"

class TestResultDetail(models.Model):
    result = models.ForeignKey(TestResult, on_delete=models.CASCADE, related_name='details')
    word_question = models.CharField(max_length=100)
    student_answer = models.CharField(max_length=100)
    correct_answer = models.CharField(max_length=100)
    is_correct = models.BooleanField(default=False)
    is_correction_requested = models.BooleanField(default=False, verbose_name="정답 정정 요청")
    is_resolved = models.BooleanField(default=False, verbose_name="처리 완료")

    def __str__(self):
        return f"{self.word_question} ({'O' if self.is_correct else 'X'})"


# 2-2. 월말 평가 결과
class MonthlyTestResult(models.Model):
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='monthly_results')
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
# [4] 기록 제거시 5분 쿨타임 제거
# ==========================================
@receiver(post_delete, sender=TestResult)
def auto_reset_cooldown(sender, instance, **kwargs):
    """
    선생님이 시험 결과를 삭제하면, 
    해당 학생의 쿨타임(5분 제한)을 다시 확인해서 풀어주는 자동화 기능
    """
    student = instance.student
    
    # 학생 프로필이 없으면 패스
    if not hasattr(student, 'profile'):
        return

    profile = student.profile
    now = timezone.now()
    five_mins_ago = now - timedelta(minutes=5)

    # 1. [도전 모드] 쿨타임 검사
    # 최근 5분 내에 '27점 미만'인 기록이 아직 남아있는지 확인
    recent_challenge_fails = TestResult.objects.filter(
        student=student,
        score__lt=27,
        created_at__gte=five_mins_ago
    ).exclude(test_range="오답집중") # 오답모드 기록은 제외

    # 남은 실패 기록이 없다면 -> 쿨타임 해제!
    if not recent_challenge_fails.exists():
        profile.last_failed_at = None

    # 2. [오답 탈출 모드] 쿨타임 검사
    recent_wrong_fails = TestResult.objects.filter(
        student=student,
        score__lt=27,
        created_at__gte=five_mins_ago,
        test_range="오답집중" # 오답모드 기록만 확인
    )

    # 남은 실패 기록이 없다면 -> 쿨타임 해제!
    if not recent_wrong_fails.exists():
        profile.last_wrong_failed_at = None

    profile.save()