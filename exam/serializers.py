from rest_framework import serializers
from .models import ExamResult, TestPaper

class ExamResultSerializer(serializers.ModelSerializer):
    paper_title = serializers.CharField(source='paper.title', read_only=True)
    
    class Meta:
        model = ExamResult
        fields = ['id', 'paper_title', 'score', 'date']
