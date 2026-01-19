from rest_framework import serializers
from .models import MonthlyReport, ReportShare

class MonthlyReportSerializer(serializers.ModelSerializer):
    class Meta:
        model = MonthlyReport
        fields = '__all__'

class ReportShareSerializer(serializers.ModelSerializer):
    link = serializers.SerializerMethodField()
    
    class Meta:
        model = ReportShare
        fields = ['uuid', 'student', 'created_at', 'expires_at', 'link']
    
    def get_link(self, obj):
        # 실제 도메인으로 변경 필요
        return f"https://blossomedu.com/reports/view/{obj.uuid}/"
