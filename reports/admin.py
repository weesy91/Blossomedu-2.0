from django.contrib import admin
from .models import OfflineTestResult, MonthlyReport

@admin.register(OfflineTestResult)
class OfflineTestResultAdmin(admin.ModelAdmin):
    list_display = ('exam_date', 'student_name', 'syntax_score', 'reading_score')
    list_filter = ('exam_date',)
    search_fields = ('student__profile__name',)

    def student_name(self, obj):
        return obj.student.profile.name

@admin.register(MonthlyReport)
class MonthlyReportAdmin(admin.ModelAdmin):
    list_display = ('year', 'month', 'student_name', 'average_word_score', 'created_at')
    list_filter = ('year', 'month')
    
    def student_name(self, obj):
        return obj.student.profile.name