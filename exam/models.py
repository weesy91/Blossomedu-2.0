from django.db import models
from django.conf import settings
from core.models import StudentProfile

# ==========================================
# [1] 문제은행 (Question Bank)
# ==========================================
class QuestionGroup(models.Model):
    """
    지문 하나에 문제 여러 개가 딸린 경우 (세트 문제) 대비
    """
    title = models.CharField(max_length=200, verbose_name="지문 제목/주제", blank=True)
    content = models.TextField(verbose_name="공통 지문 내용", blank=True)
    
    def __str__(self):
        return self.title or f"지문 #{self.id}"

class Question(models.Model):
    CATEGORY_CHOICES = [
        ('SYNTAX', '구문'),
        ('GRAMMAR', '어법'),
        ('READING', '독해'),
    ]

    STYLE_CHOICES = [
        ('CONCEPT', '🟢 개념/이론'),
        ('ANALYSIS', '🔴 구문분석/적용'),
    ]
    READING_TYPE_CHOICES = (
        ('NONE', '해당없음 (구문/개념 등)'),
        ('TOPIC', 'Type A: 대의파악 (주제/제목/요지)'),
        ('LOGIC', 'Type B: 논리흐름 (순서/삽입/무관)'),
        ('BLANK', 'Type C: 빈칸/함축의미'),
        ('DETAIL', 'Type D: 세부내용 (일치/도표/어휘)'),
        ('STRUCT', 'Type S: 문장 구조분석 (가로 1단)')
    )
    
    reading_type = models.CharField(
        max_length=10, 
        choices=READING_TYPE_CHOICES, 
        default='NONE',
        verbose_name="독해 유형"
    )

    
    # 1. 문제 출처 정보
    # (academy앱의 Textbook 모델과 연결할 수도 있지만, 독립성을 위해 일단 문자열로 저장)
    book_name = models.CharField(max_length=100, verbose_name="교재명") 
    chapter = models.IntegerField(default=1, verbose_name="강/챕터")
    number = models.CharField(max_length=20, verbose_name="문제 번호")
    
    category = models.CharField(max_length=10, choices=CATEGORY_CHOICES, default='SYNTAX', verbose_name="유형")
    
    style = models.CharField(
        max_length=10, 
        choices=STYLE_CHOICES, 
        default='CONCEPT', 
        verbose_name="문제 유형"
    )

    # 2. 문제 내용
    group = models.ForeignKey(QuestionGroup, on_delete=models.SET_NULL, null=True, blank=True, verbose_name="지문 그룹")
    question_text = models.TextField(verbose_name="문제 지문/내용")
    
    # 이미지가 필요한 문제일 경우를 대비
    image = models.ImageField(upload_to='exam_images/', null=True, blank=True, verbose_name="문제 이미지")
    answer_image = models.ImageField(upload_to='exam_answers/', null=True, blank=True, verbose_name="해설 이미지")
    # 3. 정답 및 해설 (교사용 PDF에서 추출)
    answer = models.CharField(max_length=200, verbose_name="정답", blank=True)
    explanation = models.TextField(verbose_name="해설/이유", blank=True)
    
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "문제"
        verbose_name_plural = "문제 관리"
        ordering = ['book_name', 'chapter', 'number']
        unique_together = ('book_name', 'chapter', 'number') # 중복 등록 방지

    def __str__(self):
        return f"[{self.book_name}] {self.chapter}강 - {self.number}번"


# ==========================================
# [2] 시험지 (Test Paper)
# ==========================================
class TestPaper(models.Model):
    """
    자동 생성된 월말평가 시험지
    """
    student = models.ForeignKey(
        StudentProfile, 
        on_delete=models.CASCADE, 
        related_name='test_papers',
        verbose_name="응시 학생"
    )
    title = models.CharField(max_length=100, verbose_name="시험지 제목") # 예: 12월 월말평가 (김똘똘)
    
    # 어떤 범위에서 출제했는지 기록
    target_chapters = models.CharField(max_length=200, verbose_name="출제 범위") # 예: 구문 1-5강, 어법 2-4강
    
    questions = models.ManyToManyField(Question, related_name='test_papers', verbose_name="포함된 문제들")
    
    created_at = models.DateTimeField(auto_now_add=True)
    
    def __str__(self):
        return self.title


# ==========================================
# [3] 시험 결과 (Exam Result)
# ==========================================
class ExamResult(models.Model):
    paper = models.ForeignKey(TestPaper, on_delete=models.CASCADE, related_name='results')
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE)
    
    score = models.IntegerField(default=0, verbose_name="점수")
    is_passed = models.BooleanField(default=False, verbose_name="통과 여부")
    
    teacher_comment = models.TextField(blank=True, verbose_name="선생님 피드백")
    date = models.DateField(auto_now_add=True, verbose_name="응시일")

    def __str__(self):
        return f"{self.student.profile.name} - {self.paper.title}"