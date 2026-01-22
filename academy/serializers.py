from rest_framework import serializers
from .models import AssignmentTask, AssignmentSubmission, AssignmentSubmissionImage, ClassLog, ClassLogEntry, TemporarySchedule, Attendance, Textbook, TextbookUnit
from core.models import StudentProfile

class AssignmentSubmissionImageSerializer(serializers.ModelSerializer):
    image_url = serializers.SerializerMethodField()

    class Meta:
        model = AssignmentSubmissionImage
        fields = ['id', 'image', 'image_url', 'created_at']

    def get_image_url(self, obj):
        if not obj.image:
            return ''
        request = self.context.get('request')
        if request is None:
            return obj.image.url
        return request.build_absolute_uri(obj.image.url)

class AssignmentSubmissionSerializer(serializers.ModelSerializer):
    student_name = serializers.ReadOnlyField(source='student.name')
    image_url = serializers.SerializerMethodField()
    images = AssignmentSubmissionImageSerializer(many=True, read_only=True)
    
    class Meta:
        model = AssignmentSubmission
        fields = '__all__'
        read_only_fields = ['submitted_at', 'status', 'reviewed_at']

    def get_image_url(self, obj):
        if not obj.image:
            return ''
        request = self.context.get('request')
        if request is None:
            return obj.image.url
        return request.build_absolute_uri(obj.image.url)

class AssignmentTaskSerializer(serializers.ModelSerializer):
    student_name = serializers.CharField(source='student.name', read_only=True)
    submission = AssignmentSubmissionSerializer(read_only=True)
    origin_log_subject = serializers.CharField(source='origin_log.subject', read_only=True)
    lecture_links = serializers.SerializerMethodField()  # NEW: 강의 링크

    class Meta:
        model = AssignmentTask
        fields = '__all__'

    def get_lecture_links(self, obj):
        """교재 범위에 해당하는 강의 링크 반환"""
        if not obj.related_textbook or not obj.textbook_range:
            return []
        
        # Parse range (e.g., "1-3" or "5")
        range_str = obj.textbook_range.strip()
        try:
            if '-' in range_str:
                start, end = map(int, range_str.split('-'))
            else:
                start = end = int(range_str)
        except ValueError:
            return []
        
        # Get units within range
        units = obj.related_textbook.units.filter(
            unit_number__gte=start,
            unit_number__lte=end
        ).order_by('unit_number')
        
        return [
            {
                'unit_number': u.unit_number,
                'link_url': u.link_url,
                'title': f'{u.unit_number}강'
            }
            for u in units if u.link_url
        ]

class AttendanceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Attendance
        fields = ['date', 'status', 'check_in_time', 'left_at']

class TemporaryScheduleSerializer(serializers.ModelSerializer):
    subject_display = serializers.CharField(source='get_subject_display', read_only=True)
    
    class Meta:
        model = TemporarySchedule
        fields = '__all__'

class ClassLogEntrySerializer(serializers.ModelSerializer):
    textbook_title = serializers.CharField(source='textbook.title', read_only=True)
    wordbook_title = serializers.CharField(source='wordbook.title', read_only=True)
    
    class Meta:
        model = ClassLogEntry
        fields = [
            'id',
            'textbook',
            'wordbook',
            'textbook_title',
            'wordbook_title',
            'progress_range',
            'score',
        ]

class ClassLogSerializer(serializers.ModelSerializer):
    entries = ClassLogEntrySerializer(many=True, read_only=True)
    subject_display = serializers.CharField(source='get_subject_display', read_only=True)
    
    assignments = serializers.ListField(
        child=serializers.DictField(), 
        write_only=True, 
        required=False
    )
    entries_input = serializers.ListField(
        child=serializers.DictField(),
        write_only=True,
        required=False,
    )
    
    generated_assignments = AssignmentTaskSerializer(many=True, read_only=True)

    class Meta:
        model = ClassLog
        fields = [
            'id', 'student', 'date', 'subject', 'subject_display', 'comment', 'entries',
            'hw_main_book', 'hw_main_range', 'hw_due_date',
            'assignments',
            'entries_input',
            'generated_assignments', # [NEW] Read-only list of created assignments
        ]

    def validate(self, data):
        """
        [Business Rule] 결석(ABSENT) 상태인 경우 일지 작성 불가
        (Trigger Reload)
        """
        student = data.get('student')
        date = data.get('date')
        
        # update 시에는 instance에서 값을 가져와야 할 수도 있음
        if not student and self.instance: student = self.instance.student
        if not date and self.instance: date = self.instance.date

        if student and date:
            try:
                att = Attendance.objects.get(student=student, date=date)
                if att.status == 'ABSENT':
                    # Allow but maybe warn? For now strict.
                    raise serializers.ValidationError("결석(ABSENT) 처리된 학생은 일지를 작성할 수 없습니다.")
            except Attendance.DoesNotExist:
                pass 
                
        return data

    def create(self, validated_data):
        assignments_data = validated_data.pop('assignments', [])
        entries_data = validated_data.pop('entries_input', [])
        
        # 1. Create ClassLog
        instance = super().create(validated_data)
        
        # 2. Create AssignmentTasks
        for item in assignments_data:
            # [Fix] Parse due_date string to datetime object (handling ISO format)
            due_date_str = item.get('due_date')
            due_date_obj = None
            if due_date_str:
                # Assuming ISO 8601 format from frontend (e.g., "2024-01-21T22:00:00.000")
                try:
                    from dateutil import parser
                    due_date_obj = parser.parse(due_date_str)
                except ImportError:
                    # Fallback if dateutil is not available (though it usually is in django env)
                    from datetime import datetime
                    try:
                        due_date_obj = datetime.fromisoformat(due_date_str.replace('Z', '+00:00'))
                    except ValueError:
                         pass

            related_vocab_book_id = item.get('related_vocab_book')
            vocab_range_start = item.get('vocab_range_start')
            vocab_range_end = item.get('vocab_range_end')
            try:
                vocab_range_start = int(vocab_range_start) if vocab_range_start is not None else None
            except (TypeError, ValueError):
                vocab_range_start = None
            try:
                vocab_range_end = int(vocab_range_end) if vocab_range_end is not None else None
            except (TypeError, ValueError):
                vocab_range_end = None

            if due_date_obj:
                # [NEW] Auto-calculate start_date only for VOCAB_TEST (단어 과제만 잠금)
                from datetime import timedelta
                assignment_type = item.get('assignment_type', 'MANUAL')
                start_date_obj = None
                if assignment_type == 'VOCAB_TEST':
                    start_date_obj = due_date_obj.replace(
                        hour=0,
                        minute=0,
                        second=0,
                        microsecond=0,
                    ) - timedelta(days=1)
                
                AssignmentTask.objects.create(
                    student=instance.student,
                    teacher=instance.teacher, 
                    origin_log=instance,
                    title=item.get('title', '과제'),
                    description=item.get('description', ''),
                    assignment_type=assignment_type,
                    due_date=due_date_obj,
                    start_date=start_date_obj,  # [NEW] VOCAB_TEST만 마감 하루 전부터 수행 가능
                    related_vocab_book_id=related_vocab_book_id,
                    vocab_range_start=vocab_range_start or 0,
                    vocab_range_end=vocab_range_end or 0,
                    # [FIX] Support Textbook Links
                    related_textbook_id=item.get('related_textbook'),
                    textbook_range=item.get('textbook_range', ''),
                    is_cumulative=item.get('is_cumulative', False),
                )

        # 3. Create ClassLogEntries (Today's Lesson)
        for item in entries_data:
            progress_range = item.get('progress_range')
            if not progress_range:
                continue
            ClassLogEntry.objects.create(
                class_log=instance,
                textbook_id=item.get('textbook'),
                wordbook_id=item.get('wordbook'),
                progress_range=progress_range,
                score=item.get('score') or '',
            )
            
        return instance

    def update(self, instance, validated_data):
        assignments_data = validated_data.pop('assignments', None)
        entries_data = validated_data.pop('entries_input', None)

        instance = super().update(instance, validated_data)

        if assignments_data is None:
            return instance

        def _signature_from_data(data):
            assignment_type = data.get('assignment_type', 'MANUAL')
            title = (data.get('title') or '').strip()
            related_vocab_book_id = data.get('related_vocab_book') or 0
            vocab_range_start = data.get('vocab_range_start') or 0
            vocab_range_end = data.get('vocab_range_end') or 0
            try:
                vocab_range_start = int(vocab_range_start)
            except (TypeError, ValueError):
                vocab_range_start = 0
            try:
                vocab_range_end = int(vocab_range_end)
            except (TypeError, ValueError):
                vocab_range_end = 0
            is_cumulative = data.get('is_cumulative', False) is True
            description = (data.get('description') or '').strip()
            return (
                assignment_type,
                title,
                related_vocab_book_id or 0,
                vocab_range_start,
                vocab_range_end,
                is_cumulative,
                description,
            )

        def _signature_from_task(task):
            return (
                task.assignment_type,
                (task.title or '').strip(),
                task.related_vocab_book_id or 0,
                task.vocab_range_start or 0,
                task.vocab_range_end or 0,
                task.is_cumulative is True,
                (task.description or '').strip(),
            )

        incoming_signatures = {
            _signature_from_data(item) for item in assignments_data or []
        }
        submitted_task_ids = set(
            AssignmentSubmission.objects.filter(task__origin_log=instance)
            .values_list('task_id', flat=True)
        )
        completed_task_ids = set(
            AssignmentTask.objects.filter(origin_log=instance, is_completed=True)
            .values_list('id', flat=True)
        )
        keep_task_ids = completed_task_ids | submitted_task_ids
        existing_signatures_by_id = {
            task.id: _signature_from_task(task)
            for task in AssignmentTask.objects.filter(origin_log=instance)
        }

        for task in AssignmentTask.objects.filter(origin_log=instance):
            if not (task.is_completed or task.id in submitted_task_ids):
                continue
            should_replace = _signature_from_task(task) not in incoming_signatures
            if task.is_replaced != should_replace:
                task.is_replaced = should_replace
                task.save(update_fields=['is_replaced'])

        # Remove only non-submitted/non-completed tasks before recreating.
        for task in AssignmentTask.objects.filter(origin_log=instance):
            if task.is_completed:
                continue
            try:
                _ = task.submission
                continue
            except Exception:
                pass
            task.delete()

        for item in assignments_data:
            item_id = item.get('id')
            try:
                item_id = int(item_id) if item_id is not None else None
            except (TypeError, ValueError):
                item_id = None
            if item_id is not None and item_id in keep_task_ids:
                existing_signature = existing_signatures_by_id.get(item_id)
                if existing_signature == _signature_from_data(item):
                    continue
            due_date_str = item.get('due_date')
            due_date_obj = None
            if due_date_str:
                try:
                    from dateutil import parser
                    due_date_obj = parser.parse(due_date_str)
                except ImportError:
                    from datetime import datetime
                    try:
                        due_date_obj = datetime.fromisoformat(
                            due_date_str.replace('Z', '+00:00')
                        )
                    except ValueError:
                        pass

            related_vocab_book_id = item.get('related_vocab_book')
            vocab_range_start = item.get('vocab_range_start')
            vocab_range_end = item.get('vocab_range_end')
            try:
                vocab_range_start = int(vocab_range_start) if vocab_range_start is not None else None
            except (TypeError, ValueError):
                vocab_range_start = None
            try:
                vocab_range_end = int(vocab_range_end) if vocab_range_end is not None else None
            except (TypeError, ValueError):
                vocab_range_end = None

            if due_date_obj:
                # [NEW] Auto-calculate start_date only for VOCAB_TEST (단어 과제만 잠금)
                from datetime import timedelta
                assignment_type = item.get('assignment_type', 'MANUAL')
                start_date_obj = None
                if assignment_type == 'VOCAB_TEST':
                    start_date_obj = due_date_obj.replace(
                        hour=0,
                        minute=0,
                        second=0,
                        microsecond=0,
                    ) - timedelta(days=1)
                
                AssignmentTask.objects.create(
                    student=instance.student,
                    teacher=instance.teacher,
                    origin_log=instance,
                    title=item.get('title', '과제'),
                    description=item.get('description', ''),
                    assignment_type=assignment_type,
                    due_date=due_date_obj,
                    start_date=start_date_obj,  # [NEW] VOCAB_TEST만 마감 하루 전부터 수행 가능
                    related_vocab_book_id=related_vocab_book_id,
                    vocab_range_start=vocab_range_start or 0,
                    vocab_range_end=vocab_range_end or 0,
                    # [FIX] Support Textbook Links in update (same as create)
                    related_textbook_id=item.get('related_textbook'),
                    textbook_range=item.get('textbook_range', ''),
                    is_cumulative=item.get('is_cumulative', False),
                )

        if entries_data is None:
            return instance

        instance.entries.all().delete()
        for item in entries_data:
            progress_range = item.get('progress_range')
            if not progress_range:
                continue
            ClassLogEntry.objects.create(
                class_log=instance,
                textbook_id=item.get('textbook'),
                wordbook_id=item.get('wordbook'),
                progress_range=progress_range,
                score=item.get('score') or '',
            )

        return instance

class TextbookUnitSerializer(serializers.ModelSerializer):
    class Meta:
        model = TextbookUnit
        fields = ['id', 'unit_number', 'link_url']

class TextbookSerializer(serializers.ModelSerializer):
    units = TextbookUnitSerializer(many=True, required=False) # Writable
    category_display = serializers.CharField(source='get_category_display', read_only=True)

    class Meta:
        model = Textbook
        fields = ['id', 'title', 'publisher', 'level', 'category', 'category_display', 'total_units', 'units', 'has_ot']

    def create(self, validated_data):
        units_data = validated_data.pop('units', [])
        textbook = Textbook.objects.create(**validated_data)
        for unit_data in units_data:
            TextbookUnit.objects.create(textbook=textbook, **unit_data)
        return textbook

    def update(self, instance, validated_data):
        units_data = validated_data.pop('units', None)
        
        # Update fields
        instance.title = validated_data.get('title', instance.title)
        instance.publisher = validated_data.get('publisher', instance.publisher)
        instance.level = validated_data.get('level', instance.level)
        instance.category = validated_data.get('category', instance.category)
        instance.total_units = validated_data.get('total_units', instance.total_units)
        instance.save()

        # Update units if provided
        if units_data is not None:
            # Simple strategy: Delete all and recreate? Or smart update?
            # Simplest for now: Delete and Recreate (safe for small number of units)
            instance.units.all().delete()
            for unit_data in units_data:
                TextbookUnit.objects.create(textbook=instance, **unit_data)
        
        return instance
