from rest_framework import serializers
from .models import MockExam, MockExamInfo, MockExamQuestion

class MockExamQuestionSerializer(serializers.ModelSerializer):
    class Meta:
         model = MockExamQuestion
         fields = ['id', 'number', 'score', 'category', 'correct_answer']

class MockExamInfoSerializer(serializers.ModelSerializer):
    questions = MockExamQuestionSerializer(many=True, read_only=True)
    class Meta:
        model = MockExamInfo
        fields = ['id', 'year', 'month', 'grade', 'title', 'questions', 'institution']

class MockExamSerializer(serializers.ModelSerializer):
    class Meta:
        model = MockExam
        fields = ['id', 'exam_date', 'title', 'score', 'grade', 'note', 'total_wrong', 'wrong_vocab', 'wrong_grammar', 'wrong_reading', 'wrong_listening', 'wrong_type_breakdown']

# [NEW] Input Serializers for OMR Confirmation
class MockExamResultItemSerializer(serializers.Serializer):
    student_id = serializers.IntegerField() # DB ID of StudentProfile
    score = serializers.IntegerField()
    grade = serializers.IntegerField()
    wrong_counts = serializers.DictField()
    wrong_type_breakdown = serializers.DictField()
    wrong_question_numbers = serializers.ListField(child=serializers.IntegerField())
    student_answers = serializers.DictField()

class MockExamConfirmSerializer(serializers.Serializer):
    exam_id = serializers.IntegerField()
    results = MockExamResultItemSerializer(many=True)
