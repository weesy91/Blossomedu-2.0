from django.db import models
from django.conf import settings

class OfflineTestResult(models.Model):
    """
    [오프라인 시험 점수 관리]
    - 구문(Syntax) 및 독해(Reading) 시험 점수를 입력하는 곳입니다.
    - 단어 점수는 vocab 앱에서 자동으로 가져오므로 여기엔 없습니다.
    """
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='offline_results')
    exam_date = models.DateField(verbose_name="시험 날짜")
    
    # 점수 필드 (100점 만점 기준)
    syntax_score = models.IntegerField(default=0, verbose_name="구문 점수")
    reading_score = models.IntegerField(default=0, verbose_name="독해 점수")
    
    # 피드백
    feedback = models.TextField(blank=True, verbose_name="선생님 코멘트")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "구문/독해 점수(오프라인)"
        verbose_name_plural = "구문/독해 점수(오프라인)"
        ordering = ['-exam_date']

    def __str__(self):
        return f"[{self.exam_date}] {self.student.profile.name} - 구문:{self.syntax_score} / 독해:{self.reading_score}"


class MonthlyReport(models.Model):
    """
    [최종 월말 성적표]
    - '단어 + 구문 + 독해'를 모두 합쳐서 학부모님께 보내는 최종 성적표입니다.
    - 이 데이터가 생성되면 '발송 완료'된 것으로 간주할 수 있습니다.
    """
    student = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='monthly_reports')
    year = models.IntegerField(verbose_name="년도")
    month = models.IntegerField(verbose_name="월")
    
    # 스냅샷 저장 (나중에 단어 점수가 바뀌어도 성적표는 그대로 유지되도록 값을 복사해둠)
    average_word_score = models.FloatField(verbose_name="단어 평균 점수", help_text="도전모드/월말평가 평균")
    syntax_score = models.IntegerField(verbose_name="구문 점수")
    reading_score = models.IntegerField(verbose_name="독해 점수")
    
    overall_comment = models.TextField(verbose_name="종합 평가")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "최종 월말 성적표"
        verbose_name_plural = "최종 월말 성적표"
        unique_together = ('student', 'year', 'month')

    def __str__(self):
        return f"{self.year}년 {self.month}월 - {self.student.profile.name} 성적표"