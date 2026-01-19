from rest_framework import serializers
from .models import MockExam

class MockExamSerializer(serializers.ModelSerializer):
    class Meta:
        model = MockExam
        fields = ['id', 'exam_date', 'title', 'score', 'grade', 'note', 'total_wrong', 'wrong_vocab', 'wrong_grammar', 'wrong_reading', 'wrong_listening']
