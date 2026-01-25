from rest_framework import serializers
from .models import WordBook, Word, TestResult, TestResultDetail, PersonalWrongWord, WordMeaning, Publisher, RankingEvent
from core.models import Branch, School
from . import services

from django.db.models import Max

class WordBookSerializer(serializers.ModelSerializer):
    publisher = serializers.PrimaryKeyRelatedField(
        queryset=Publisher.objects.all(),
        required=False,
        allow_null=True
    )
    
    # [NEW] Explicitly allow null for target fields
    target_branch = serializers.PrimaryKeyRelatedField(
        queryset=Branch.objects.all(),
        required=False,
        allow_null=True
    )
    target_school = serializers.PrimaryKeyRelatedField(
        queryset=School.objects.all(),
        required=False,
        allow_null=True
    )
    target_grade = serializers.IntegerField(required=False, allow_null=True)

    publisher_name = serializers.CharField(source='publisher.name', read_only=True, default=None)
    total_words = serializers.IntegerField(source='words.count', read_only=True)
    total_days = serializers.SerializerMethodField()
    
    class Meta:
        model = WordBook
        fields = [
            'id', 'title', 'publisher', 'publisher_name', 'total_words', 'total_days',
            'csv_file', 'cover_image', 'target_branch', 'target_school', 'target_grade', 
            'created_at'
        ]

    def get_total_days(self, obj):
        max_day = obj.words.aggregate(Max('number'))['number__max']
        return max_day or 0


class PublisherSerializer(serializers.ModelSerializer):
    class Meta:
        model = Publisher
        fields = ['id', 'name']

class RankingEventSerializer(serializers.ModelSerializer):
    target_book_title = serializers.CharField(
        source='target_book.title', read_only=True
    )
    branch_name = serializers.CharField(source='branch.name', read_only=True)

    class Meta:
        model = RankingEvent
        fields = [
            'id',
            'title',
            'target_book',
            'target_book_title',
            'branch',
            'branch_name',
            'start_date',
            'end_date',
            'is_active',
        ]

class WordSerializer(serializers.ModelSerializer):
    pos = serializers.SerializerMethodField()
    meaning_groups = serializers.SerializerMethodField()

    class Meta:
        model = Word
        fields = ['id', 'english', 'korean', 'number', 'example_sentence', 'pos', 'meaning_groups']

    def get_pos(self, obj):
        # Keep this for backward compatibility or simple filtering
        groups = self.get_meaning_groups(obj)
        return sorted(list(set(g['pos'] for g in groups)))

    def get_meaning_groups(self, obj):
        # "일치하다, 일치, 협정" -> [{'pos': 'v', 'meaning': '일치하다'}, {'pos': 'n', 'meaning': '일치, 협정'}]
        if not obj.korean:
            return []

        entries = services.parse_meaning_tokens(obj.korean)
        if not entries:
            return []

        meaning_list = [e['meaning'] for e in entries]
        meaning_pos_map = {}
        if obj.master_word_id:
            meanings = WordMeaning.objects.filter(
                master_word=obj.master_word,
                meaning__in=meaning_list,
            )
            meaning_pos_map = {
                m.meaning: services._normalize_pos_tag(m.pos)
                for m in meanings
            }

        grouped = {}
        for entry in entries:
            pos = entry['pos']
            if not entry['manual']:
                pos = meaning_pos_map.get(entry['meaning'], pos)
            pos = services._normalize_pos_tag(pos) or 'n'
            if pos not in grouped:
                grouped[pos] = []
            grouped[pos].append(entry['meaning'])

        # Sort Order
        order = ['v', 'adj', 'adv', 'n', 'pron', 'prep', 'conj', 'interj']
        result = []
        for tag in order:
            if tag in grouped:
                result.append({
                    'pos': tag,
                    'meaning': ', '.join(grouped[tag])
                })

        # Add any remaining tags not in order (unlikely with current logic but for safety)
        for tag in grouped:
            if tag not in order:
                result.append({
                    'pos': tag,
                    'meaning': ', '.join(grouped[tag])
                })

        return result


class TestResultDetailSerializer(serializers.ModelSerializer):
    class Meta:
        model = TestResultDetail
        fields = ['id', 'word_question', 'question_pos', 'student_answer', 'correct_answer', 'is_correct', 'is_correction_requested', 'is_resolved']

class TestResultSummarySerializer(serializers.ModelSerializer):
    book_title = serializers.CharField(source='book.title', read_only=True)
    student_name = serializers.CharField(source='student.name', read_only=True)

    class Meta:
        model = TestResult
        fields = ['id', 'student_name', 'book_title', 'score', 'wrong_count', 'test_range', 'created_at']

class TestResultSerializer(serializers.ModelSerializer):
    book_title = serializers.CharField(source='book.title', read_only=True)
    student_name = serializers.CharField(source='student.name', read_only=True)
    assignment = serializers.CharField(source='assignment_id', read_only=True)
    details = TestResultDetailSerializer(many=True, read_only=True)
    
    class Meta:
        model = TestResult
        fields = ['id', 'student_name', 'book_title', 'score', 'wrong_count', 'test_range', 'created_at', 'details', 'assignment']

class PersonalWrongWordSerializer(serializers.ModelSerializer):
    english = serializers.CharField(source='word.english', read_only=True)
    korean = serializers.CharField(source='word.korean', read_only=True)
    
    class Meta:
        model = PersonalWrongWord
        fields = ['id', 'word_id', 'created_at', 'english', 'korean']
