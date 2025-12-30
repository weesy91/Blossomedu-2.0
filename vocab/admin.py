from django.contrib import admin
from django.http import HttpResponse
from django.utils.html import format_html
from django.shortcuts import render, get_object_or_404
from .models import WordBook, Word, TestResult, TestResultDetail, MonthlyTestResult, MonthlyTestResultDetail, Publisher

# 1. 단어장 (WordBook) 관리
class WordInline(admin.TabularInline):
    model = Word
    extra = 3

@admin.register(WordBook)
class WordBookAdmin(admin.ModelAdmin):
    list_display = ('title', 'publisher', 'created_at')
    inlines = [WordInline]

# 2. 출판사 (Publisher) 관리
@admin.register(Publisher)
class PublisherAdmin(admin.ModelAdmin):
    list_display = ('name',)

    # [최후의 수단] 팝업 저장 후 강제로 창을 닫아버리는 함수
    def response_add(self, request, obj, post_url_continue=None):
        # 팝업창에서 저장을 눌렀다면?
        if "_popup" in request.POST:
            # 브라우저에게 "묻지 말고 그냥 닫아!"라고 명령합니다.
            # (부모 창을 새로고침해서 데이터를 갱신시킵니다)
            return HttpResponse('''
                <script type="text/javascript">
                    window.close();
                    if (window.opener && !window.opener.closed) {
                        window.opener.location.reload();
                    }
                </script>
            ''')
        return super().response_add(request, obj, post_url_continue)
    
# 3. 도전 모드 결과 (TestResult) 관리
@admin.register(TestResult)
class TestResultAdmin(admin.ModelAdmin):
    # [수정] 목록에 'get_book_title', 'get_test_range' 추가
    list_display = ('student_name', 'get_book_title', 'get_test_range', 'score_display', 'wrong_count', 'created_at')
    list_filter = ('created_at', 'score', 'book') # 필터에도 책 추가
    search_fields = ('student__username', 'student__profile__name', 'book__title')

    def student_name(self, obj):
        return obj.student.profile.name if hasattr(obj.student, 'profile') else obj.student.username
    student_name.short_description = "학생 이름"

    # [추가] 단어장 제목 표시
    def get_book_title(self, obj):
        return obj.book.title if obj.book else "-"
    get_book_title.short_description = "단어장"

    # [추가] 시험 범위 표시 (오답모드 문구 변환 포함)
    def get_test_range(self, obj):
        return "오답단어" if obj.test_range == "오답집중" else obj.test_range
    get_test_range.short_description = "시험 범위"

    def score_display(self, obj):
        if obj.score >= 27:
            return format_html('<span style="color:green; font-weight:bold;">{}점 (통과)</span>', obj.score)
        return format_html('<span style="color:red; font-weight:bold;">{}점 (재시험)</span>', obj.score)
    score_display.short_description = "점수"

    def change_view(self, request, object_id, form_url='', extra_context=None):
        result = get_object_or_404(TestResult, pk=object_id)
        details = TestResultDetail.objects.filter(result=result).order_by('id')
        
        context = {
            'result': result,
            'details': details,
            'opts': self.model._meta,
            'has_view_permission': True,
            'back_url': '/admin/vocab/testresult/'
        }
        return render(request, 'vocab/admin_result_detail.html', context)

# 4. 월말 평가 결과 (MonthlyTestResult) 관리
@admin.register(MonthlyTestResult)
class MonthlyTestResultAdmin(admin.ModelAdmin):
    # [수정] 목록에 단어장/범위 추가
    list_display = ('student_name', 'get_book_title', 'get_test_range', 'score_display', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('student__username', 'student__profile__name', 'book__title')

    def student_name(self, obj):
        return obj.student.profile.name if hasattr(obj.student, 'profile') else obj.student.username
    student_name.short_description = "학생 이름"

    # [추가] 단어장 제목
    def get_book_title(self, obj):
        return obj.book.title if obj.book else "전체 범위"
    get_book_title.short_description = "단어장"

    # [추가] 범위
    def get_test_range(self, obj):
        return obj.test_range
    get_test_range.short_description = "시험 범위"

    def score_display(self, obj):
        if obj.score >= 85:
            return format_html('<span style="color:green; font-weight:bold;">{}점 (통과)</span>', obj.score)
        return format_html('<span style="color:red; font-weight:bold;">{}점 (불합격)</span>', obj.score)
    score_display.short_description = "점수"

    def change_view(self, request, object_id, form_url='', extra_context=None):
        result = get_object_or_404(MonthlyTestResult, pk=object_id)
        details = MonthlyTestResultDetail.objects.filter(result=result).order_by('id')
        
        context = {
            'result': result,
            'details': details,
            'opts': self.model._meta,
            'has_view_permission': True,
            'back_url': '/admin/vocab/monthlytestresult/'
        }
        return render(request, 'vocab/admin_result_detail.html', context)