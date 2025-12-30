from django.contrib import admin
from .models import Question, QuestionGroup, TestPaper, ExamResult

@admin.register(Question)
class QuestionAdmin(admin.ModelAdmin):
    # 리스트에서 보여줄 칼럼들
    list_display = ('book_name', 'category', 'chapter_info', 'number', 'short_question')
    # 필터링 기능 (우측 사이드바)
    list_filter = ('book_name', 'category', 'chapter')
    # 검색 기능 (상단 검색창)
    search_fields = ('question_text', 'explanation', 'book_name')
    # 페이지당 보여줄 개수
    list_per_page = 20

    # 챕터 정보를 예쁘게 표시
    def chapter_info(self, obj):
        return f"{obj.chapter}강"
    chapter_info.short_description = "진도"

    # 문제 내용을 짧게 줄여서 표시
    def short_question(self, obj):
        return obj.question_text[:50] + "..." if len(obj.question_text) > 50 else obj.question_text
    short_question.short_description = "문제 미리보기"

# 나머지 모델들도 등록
admin.site.register(QuestionGroup)
admin.site.register(TestPaper)
admin.site.register(ExamResult)