from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from .models import WordBook, Word, TestResult, TestResultDetail, MonthlyTestResult, MonthlyTestResultDetail, PersonalWrongWord, Publisher, PersonalWordBook, MasterWord, RankingEvent
from .serializers import (
    WordBookSerializer,
    WordSerializer,
    TestResultSerializer,
    TestResultSummarySerializer,
    PersonalWrongWordSerializer,
    PublisherSerializer,
    RankingEventSerializer,
)
from . import services, utils # 기존 로직 재사용
from django.db import transaction
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.db.models import Q
from collections import defaultdict
from datetime import timedelta, datetime
import random

def _normalize_word_key(text):
    if not text:
        return ''
    return text.strip().lower()

def _update_word_state(word_state, word_key, is_correct, current_count):
    prev = word_state.get(word_key)
    if prev is True and not is_correct:
        current_count -= 1
    if prev is not True and is_correct:
        current_count += 1
    word_state[word_key] = is_correct
    return current_count

class VocabViewSet(viewsets.ModelViewSet):
    """
    단어장 및 단어 조회 API
    """
    serializer_class = WordBookSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        # [FIX] Exclude internal publishers (SYSTEM, 개인단어장) for all users
        qs = WordBook.objects.exclude(
            publisher__name__in=['SYSTEM', '개인단어장']
        ).order_by('-created_at')
        
        # 1. 선생님/관리자: 전체 조회 (시스템/개인 단어장 제외)
        if user.is_staff or user.is_superuser:
            return qs
        
        # 2. 학생: Action에 따른 분기
        if hasattr(user, 'profile'):
            profile = user.profile
            
            # (1) 목록 조회 (My Books): 내가 구독한 책만
            if self.action == 'list':
                return qs.filter(subscribers__student=profile)
            
            # (2) 상세 조회/구독 등 (Retrieve, Subscribe): 구독 안했어도 볼 수 있는 책이면 OK
            # available 로직과 동일한 가시성 필터 적용
            branch_filter = Q(target_branch__isnull=True) | Q(target_branch=profile.branch)
            school_filter = Q(target_school__isnull=True) | Q(target_school=profile.school)
            grade_filter = Q(target_grade__isnull=True) | Q(target_grade=profile.current_grade)
            
            # 이미 구독한 책도 접근 가능해야 하므로, (가시성 필터) OR (이미 구독함)
            # 사실 이미 구독한 책은 가시성 필터에 포함 안 될 수도 있음(전학 등으로?) -> 그래도 내 책이면 보여야 함.
            my_sub = Q(subscribers__student=profile)
            visible = (branch_filter & school_filter & grade_filter)
            
            return qs.filter(visible | my_sub).distinct()
            
        return qs.none()

    def perform_create(self, serializer):
        serializer.save(uploaded_by=self.request.user)

    @action(detail=False, methods=['get'])
    def available(self, request):
        """
        [NEW] '새 교재 추가'를 위한 전체 교재 목록 조회
        - 이미 추가한 교재 제외
        - 지점 필터만 적용 (타학교 교재도 추가 가능하게 허용)
        """
        user = request.user
        if not hasattr(user, 'profile'):
             return Response([])
             
        profile = user.profile
        
        # 1. 지점 필터: 전사(None) 또는 내 지점
        branch_filter = Q(target_branch__isnull=True) | Q(target_branch=profile.branch)
        
        # 2. 학교 필터: 전체(None) 또는 내 학교
        school_filter = Q(target_school__isnull=True) | Q(target_school=profile.school)
        
        # 3. 학년 필터: 전체(None) 또는 내 학년
        grade_filter = Q(target_grade__isnull=True) | Q(target_grade=profile.current_grade)
        
        qs = WordBook.objects.filter(
             branch_filter & school_filter & grade_filter
        ).exclude(
            subscribers__student=profile # 이미 추가한 것 제외
        ).exclude(
            publisher__name__in=['SYSTEM', '개인단어장'] # [NEW] 시스템/개인 단어장 제외
        ).order_by('-created_at')
        
        serializer = self.get_serializer(qs, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def subscribe(self, request, pk=None):
        """[NEW] 내 단어장에 추가"""
        book = self.get_object()
        if hasattr(request.user, 'profile'):
            profile = request.user.profile
            PersonalWordBook.objects.get_or_create(student=profile, book=book)
            return Response({'status': 'subscribed'})
        return Response({'error': 'Not a student'}, status=status.HTTP_400_BAD_REQUEST)

    @action(detail=False, methods=['get'])
    def stats(self, request):
        """
        [NEW] 대시보드 통계 (내 단어장 수, 오답 단어 수)
        """
        user = request.user
        if not hasattr(user, 'profile'):
             return Response({'my_books_count': 0, 'wrong_words_count': 0})
             
        profile = user.profile
        
        # 1. 내 단어장 수 (구독한 것만)
        my_books_count = PersonalWordBook.objects.filter(student=profile).count()
        
        # 2. 오답 단어 수 (3번 성공 전인 단어들)
        wrong_qs = PersonalWrongWord.objects.filter(
            student=profile,
            success_count__lt=3
        ).select_related('word', 'master_word')
        wrong_keys = set()
        for pw in wrong_qs:
            if pw.master_word:
                wrong_keys.add(pw.master_word.text.strip().lower())
            elif pw.word:
                wrong_keys.add(pw.word.english.strip().lower())
        wrong_words_count = len(wrong_keys)
        
        return Response({
            'my_books_count': my_books_count,
            'wrong_words_count': wrong_words_count
        })

    @action(detail=True, methods=['get'])
    def words(self, request, pk=None):
        """특정 단어장의 단어 범위 조회 (day_range=1-5,7)"""
        book = self.get_object()
        range_str = request.query_params.get('day_range', 'ALL')
        
        words = Word.objects.filter(book=book)
        
        if range_str != 'ALL':
            try:
                targets = []
                for chunk in range_str.split(','):
                    if '-' in chunk:
                        s, e = map(int, chunk.split('-'))
                        targets.extend(range(s, e + 1))
                    else:
                        targets.append(int(chunk))
                words = words.filter(number__in=targets)
            except:
                pass # 파싱 실패 시 전체 반환
        
        # 랜덤 셔플 옵션
        if request.query_params.get('shuffle') == 'true':
            words = list(words)
            random.shuffle(words)
            
        serializer = WordSerializer(words, many=True)
        return Response(serializer.data)


class PublisherViewSet(viewsets.ModelViewSet):
    serializer_class = PublisherSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = Publisher.objects.all().order_by('name')

class RankingEventViewSet(viewsets.ModelViewSet):
    serializer_class = RankingEventSerializer
    permission_classes = [permissions.IsAuthenticated]
    queryset = RankingEvent.objects.select_related('target_book', 'branch').order_by('-start_date')

    def get_permissions(self):
        if self.action in ['create', 'update', 'partial_update', 'destroy']:
            return [permissions.IsAdminUser()]
        return [permissions.IsAuthenticated()]

    def get_queryset(self):
        user = self.request.user
        qs = self.queryset
        active_only = self.request.query_params.get('active') == 'true'

        if user.is_staff or user.is_superuser:
            if active_only:
                today = timezone.now().date()
                qs = qs.filter(
                    is_active=True,
                    start_date__lte=today,
                    end_date__gte=today,
                )
            return qs

        if hasattr(user, 'profile'):
            today = timezone.now().date()
            return qs.filter(
                is_active=True,
                start_date__lte=today,
                end_date__gte=today,
            ).filter(Q(branch__isnull=True) | Q(branch=user.profile.branch))

        return RankingEvent.objects.none()

    def perform_create(self, serializer):
        instance = serializer.save()
        user = self.request.user
        if (
            not instance.branch
            and 'branch' not in self.request.data
            and hasattr(user, 'staff_profile')
            and user.staff_profile.branch
        ):
            instance.branch = user.staff_profile.branch
            instance.save(update_fields=['branch'])

class TestViewSet(viewsets.ModelViewSet):
    """
    시험 및 채점 API
    """
    queryset = TestResult.objects.all()
    serializer_class = TestResultSerializer
    permission_classes = [permissions.IsAuthenticated]
    
    def get_queryset(self):
        user = self.request.user
        qs = TestResult.objects.select_related('student', 'student__user', 'book').order_by('-created_at')
        include_details = self.request.query_params.get('include_details') != 'false'
        if include_details:
            qs = qs.prefetch_related('details')

        # 1. Staff/Superuser (Teacher)
        # 1. Staff/Superuser (Teacher)
        if user.is_staff or user.is_superuser:
            # (3) Admin (Developer) -> All
            if user.is_superuser:
                return qs
            
            if hasattr(user, 'staff_profile'):
                profile = user.staff_profile
                pos = profile.position
                
                # (1) TA (Assistant) -> All
                if pos == 'TA':
                    return qs
                
                # (2) Teacher/Vice/Principal -> Assigned Students Only
                return qs.filter(
                    Q(student__syntax_teacher=user) |
                    Q(student__reading_teacher=user) |
                    Q(student__extra_class_teacher=user)
                ).distinct()
            
            return qs.none()

        # 2. Student -> Own Results
        if hasattr(user, 'profile'):
            return qs.filter(student=user.profile)
            
        return qs.none()

    def get_serializer_class(self):
        if (
            self.action == 'list'
            and self.request.query_params.get('include_details') == 'false'
        ):
            return TestResultSummarySerializer
        return super().get_serializer_class()
        
    def filter_queryset(self, queryset):
        # [NEW] Filter Pending Requests
        pending = self.request.query_params.get('pending')
        if pending == 'true':
            from django.db.models import Count, Q
            queryset = queryset.annotate(
                pending_count=Count('details', filter=Q(details__is_correction_requested=True, details__is_resolved=False))
            ).filter(pending_count__gt=0)
        return super().filter_queryset(queryset)

    def _build_growth_series(self, profile, days=7):
        end_date = timezone.now().date()
        start_date = end_date - timedelta(days=days - 1)

        details = list(
            TestResultDetail.objects.filter(
                result__student=profile,
                result__created_at__date__lte=end_date,
            ).values('word_question', 'is_correct', 'result__created_at')
        )
        monthly_details = list(
            MonthlyTestResultDetail.objects.filter(
                result__student=profile,
                result__created_at__date__lte=end_date,
            ).values('word_question', 'is_correct', 'result__created_at')
        )

        details_by_day = defaultdict(list)
        for item in details + monthly_details:
            created_at = item.get('result__created_at')
            if not created_at:
                continue
            key = _normalize_word_key(item.get('word_question'))
            if not key:
                continue
            details_by_day[created_at.date()].append({
                'key': key,
                'is_correct': item.get('is_correct', False),
                'created_at': created_at,
            })

        for day in details_by_day:
            details_by_day[day].sort(key=lambda x: x['created_at'])

        word_state = {}
        current_count = 0

        for day in sorted(details_by_day.keys()):
            if day >= start_date:
                break
            for item in details_by_day[day]:
                current_count = _update_word_state(
                    word_state,
                    item['key'],
                    item['is_correct'],
                    current_count,
                )

        series = []
        current_day = start_date
        while current_day <= end_date:
            for item in details_by_day.get(current_day, []):
                current_count = _update_word_state(
                    word_state,
                    item['key'],
                    item['is_correct'],
                    current_count,
                )
            series.append({'date': current_day.isoformat(), 'count': current_count})
            current_day += timedelta(days=1)

        return series

    def _build_heatmap(self, profile, days=28):
        end_date = timezone.now().date()
        start_date = end_date - timedelta(days=days - 1)

        details = TestResultDetail.objects.filter(
            result__student=profile,
            result__created_at__date__gte=start_date,
            result__created_at__date__lte=end_date,
        ).values('word_question', 'result__created_at')
        monthly_details = MonthlyTestResultDetail.objects.filter(
            result__student=profile,
            result__created_at__date__gte=start_date,
            result__created_at__date__lte=end_date,
        ).values('word_question', 'result__created_at')

        day_words = defaultdict(set)
        for item in list(details) + list(monthly_details):
            created_at = item.get('result__created_at')
            if not created_at:
                continue
            key = _normalize_word_key(item.get('word_question'))
            if not key:
                continue
            day_words[created_at.date()].add(key)

        def intensity(count):
            if count <= 0:
                return 0
            if count <= 10:
                return 1
            if count <= 30:
                return 2
            return 3

        heatmap = []
        current_day = start_date
        while current_day <= end_date:
            count = len(day_words.get(current_day, set()))
            heatmap.append({
                'date': current_day.isoformat(),
                'count': count,
                'intensity': intensity(count),
            })
            current_day += timedelta(days=1)

        return heatmap

    def _build_monthly_ranking(self, start_date):
        details = TestResultDetail.objects.filter(
            result__created_at__date__gte=start_date,
            is_correct=True,
        ).values(
            'result__student_id',
            'result__student__name',
            'result__student__user__username',
            'result__student__school__name',
            'word_question',
        )
        monthly_details = MonthlyTestResultDetail.objects.filter(
            result__created_at__date__gte=start_date,
            is_correct=True,
        ).values(
            'result__student_id',
            'result__student__name',
            'result__student__user__username',
            'result__student__school__name',
            'word_question',
        )

        student_words = defaultdict(set)
        student_meta = {}

        for item in list(details) + list(monthly_details):
            student_id = item.get('result__student_id')
            if not student_id:
                continue
            key = _normalize_word_key(item.get('word_question'))
            if not key:
                continue
            student_words[student_id].add(key)
            if student_id not in student_meta:
                name = item.get('result__student__name') or item.get(
                    'result__student__user__username'
                )
                school = item.get('result__student__school__name') or ''
                display_name = f"{name} ({school})" if school else name
                student_meta[student_id] = display_name

        ranking = []
        for student_id, words in student_words.items():
            ranking.append({
                'name': student_meta.get(student_id, 'Unknown'),
                'score': len(words),
            })

        ranking.sort(key=lambda x: x['score'], reverse=True)
        return ranking[:5]

    def _build_event_rankings(self, profile):
        today = timezone.now().date()
        events = RankingEvent.objects.filter(
            is_active=True,
            start_date__lte=today,
            end_date__gte=today,
        ).filter(Q(branch__isnull=True) | Q(branch=profile.branch)).select_related('target_book')

        event_list = []
        for event in events:
            details = TestResultDetail.objects.filter(
                result__book=event.target_book,
                result__created_at__date__gte=event.start_date,
                result__created_at__date__lte=event.end_date,
                is_correct=True,
            ).values(
                'result__student_id',
                'result__student__name',
                'result__student__user__username',
                'result__student__school__name',
                'word_question',
            )
            monthly_details = MonthlyTestResultDetail.objects.filter(
                result__book=event.target_book,
                result__created_at__date__gte=event.start_date,
                result__created_at__date__lte=event.end_date,
                is_correct=True,
            ).values(
                'result__student_id',
                'result__student__name',
                'result__student__user__username',
                'result__student__school__name',
                'word_question',
            )

            student_words = defaultdict(set)
            student_meta = {}
            for item in list(details) + list(monthly_details):
                student_id = item.get('result__student_id')
                if not student_id:
                    continue
                key = _normalize_word_key(item.get('word_question'))
                if not key:
                    continue
                student_words[student_id].add(key)
                if student_id not in student_meta:
                    name = item.get('result__student__name') or item.get(
                        'result__student__user__username'
                    )
                    school = item.get('result__student__school__name') or ''
                    display_name = f"{name} ({school})" if school else name
                    student_meta[student_id] = display_name

            rankings = [
                {'name': student_meta.get(student_id, 'Unknown'), 'score': len(words)}
                for student_id, words in student_words.items()
            ]
            rankings.sort(key=lambda x: x['score'], reverse=True)

            event_list.append({
                'id': event.id,
                'title': event.title,
                'target_book_id': event.target_book_id,
                'target_book_title': event.target_book.title,
                'start_date': event.start_date.isoformat(),
                'end_date': event.end_date.isoformat(),
                'rankings': rankings[:5],
            })

        return event_list

    @action(detail=False, methods=['get'])
    def dashboard(self, request):
        if not hasattr(request.user, 'profile'):
            return Response({
                'growth': [],
                'heatmap': [],
                'rankings': {'monthly': [], 'events': []},
            })

        profile = request.user.profile
        growth = self._build_growth_series(profile, days=7)
        heatmap = self._build_heatmap(profile, days=28)

        today = timezone.now().date()
        start_of_month = today.replace(day=1)
        monthly_ranking = self._build_monthly_ranking(start_of_month)
        event_rankings = self._build_event_rankings(profile)

        return Response({
            'growth': growth,
            'heatmap': heatmap,
            'rankings': {
                'monthly': monthly_ranking,
                'events': event_rankings,
            },
        })

    @action(detail=False, methods=['get'])
    def day_history(self, request):
        if not hasattr(request.user, 'profile'):
            return Response({'date': None, 'tests': []})

        date_str = request.query_params.get('date')
        if not date_str:
            return Response({'date': None, 'tests': []})

        try:
            target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            return Response({'error': 'Invalid date format'}, status=status.HTTP_400_BAD_REQUEST)

        profile = request.user.profile
        tests = TestResult.objects.filter(
            student=profile,
            created_at__date=target_date,
        ).select_related('book').order_by('-created_at')
        monthly_tests = MonthlyTestResult.objects.filter(
            student=profile,
            created_at__date=target_date,
        ).select_related('book').order_by('-created_at')

        records = []
        for result in tests:
            total = result.total_count or (result.score + result.wrong_count)
            records.append({
                'type': 'normal',
                'time': result.created_at.strftime('%H:%M'),
                'book_title': result.book.title,
                'score': result.score,
                'total': total,
                'wrong_count': result.wrong_count,
                'test_range': result.test_range,
            })

        for result in monthly_tests:
            records.append({
                'type': 'monthly',
                'time': result.created_at.strftime('%H:%M'),
                'book_title': result.book.title,
                'score': result.score,
                'total': result.total_questions,
                'wrong_count': max(result.total_questions - result.score, 0),
                'test_range': result.test_range,
            })

        return Response({'date': date_str, 'tests': records})

    @action(detail=False, methods=['get'])
    def start_test(self, request):
        """
        [NEW] 시험 시작 (문제지 생성)
        - 파라미터: book_id, range (예: 1-5)
        - Snowball 로직이 적용된 문제 리스트를 반환합니다.
        """
        print("DEBUG: start_test API HIT!")
        if not hasattr(request.user, 'profile'):
            print("DEBUG: start_test API called - No Profile")
            return Response({'error': 'No profile'}, status=status.HTTP_400_BAD_REQUEST)

        book_id = request.query_params.get('book_id')
        day_range = request.query_params.get('range', 'ALL')
        count_param = request.query_params.get('count')
        try:
            count = int(count_param) if count_param is not None else 30
        except ValueError:
            count = 30
        
        # [Cooldown Check] Snowball Mode (book_id=0) checks last_wrong_failed_at
        if str(book_id) == '0' or day_range == 'WRONG_ONLY':
             profile = request.user.profile
             if profile.last_wrong_failed_at:
                 from django.utils import timezone
                 from datetime import timedelta
                 diff = timezone.now() - profile.last_wrong_failed_at
                 if diff < timedelta(minutes=3):
                     wait_sec = (timedelta(minutes=3) - diff).seconds
                     minutes = wait_sec // 60
                     seconds = wait_sec % 60
                     return Response(
                         {'error': f'오답 격파 재시험 대기시간입니다. {minutes}분 {seconds}초 후 가능합니다.'},
                         status=status.HTTP_429_TOO_MANY_REQUESTS
                     )

        is_wrong_only = str(book_id) == '0' or day_range == 'WRONG_ONLY'
        if is_wrong_only:
            raw_candidates = utils.get_vulnerable_words(request.user.profile)
            if not raw_candidates:
                return Response({'questions': []})
            random.shuffle(raw_candidates)
            selected = raw_candidates[:count]
            questions = []
            for w in selected:
                pos_tag = services.get_primary_pos(w.korean) if w.korean else None
                # [FIX] Build meaning_groups for POS display
                meaning_groups = []
                if w.korean:
                    grouped, _ = services.split_meanings_by_pos(w.korean)
                    order = ['v', 'adj', 'adv', 'n', 'pron', 'prep', 'conj', 'interj']
                    for tag in order:
                        if tag in grouped:
                            meaning_groups.append({
                                'pos': tag,
                                'meaning': ', '.join(grouped[tag])
                            })
                questions.append({
                    'id': w.master_word.id if w.master_word else None,
                    'word_id': w.id,
                    'type': 'WRONG_ONLY',
                    'english': w.english,
                    'korean': w.korean,
                    'pos': pos_tag,
                    'meaning_groups': meaning_groups,  # [NEW] Include for POS display
                    'is_snowball': True
                })
            return Response({'questions': questions})

        if not book_id:
            return Response({'error': 'book_id required'}, status=status.HTTP_400_BAD_REQUEST)
            
        questions = services.generate_test_questions(
            student_profile=request.user.profile,
            book_id=book_id,
            day_range=day_range,
            total_count=count
        )
        
        return Response({'questions': questions})

    @action(detail=False, methods=['post'])
    def submit(self, request):
        """
        시험 결과 제출 및 채점 (기존 services.calculate_score 로직 이식)
        """
        data = request.data
        print(
            "DEBUG submit_test:",
            {
                "book_id": data.get("book_id"),
                "range": data.get("range"),
                "mode": data.get("mode"),
                "details_len": len(data.get("details", [])),
                "assignment_id": data.get("assignment_id"),
            },
        )
        if not hasattr(request.user, 'profile'):
            return Response({'error': 'No profile'}, status=status.HTTP_400_BAD_REQUEST)
            
        profile = request.user.profile
        book_id = data.get('book_id')
        raw_details = data.get('details', []) # [{'english': 'apple', 'user_input': '사과'}, ...]
        test_range = data.get('range', '전체')
        mode = data.get('mode', 'practice') # challenge, wrong, practice
        is_wrong_only = str(book_id) == '0' or test_range == 'WRONG_ONLY' or mode == 'wrong'
        
        # 1. 채점 진행 (services.py 활용)
        # details_data 형식을 services.calculate_score에 맞게 변환해야 함
        # calculate_score는 {'english':..., 'korean':...} 형태를 기대함
        
        # DB에서 정답지 조회
        if not book_id and not is_wrong_only:
            return Response({'error': 'book_id required'}, status=status.HTTP_400_BAD_REQUEST)

        word_by_id = {}
        real_answers = {}

        if is_wrong_only:
            texts = [item.get('english') for item in raw_details if item.get('english')]
            word_ids = [
                int(item.get('word_id'))
                for item in raw_details
                if item.get('word_id') and str(item.get('word_id')).isdigit()
            ]
            if word_ids:
                word_by_id = {w.id: w for w in Word.objects.filter(id__in=word_ids)}
            master_words = MasterWord.objects.filter(text__in=texts).prefetch_related('meanings')
            real_answers = {
                mw.text: ", ".join(mw.meanings.values_list('meaning', flat=True))
                for mw in master_words
            }

            User = get_user_model()
            system_user = User.objects.filter(is_superuser=True).first() or request.user
            system_pub, _ = Publisher.objects.get_or_create(name='SYSTEM')
            book, _ = WordBook.objects.get_or_create(
                title='Wrong Only',
                publisher=system_pub,
                defaults={'uploaded_by': system_user},
            )
        else:
            book = WordBook.objects.get(id=book_id)
            words = Word.objects.filter(book=book)
            word_by_id = {w.id: w for w in words}
            real_answers = {w.english: w.korean for w in words}
        
        for item in raw_details:
            q = item.get('english')
            word_id = item.get('word_id')
            pos = item.get('pos')

            answer = None
            if word_id and str(word_id).isdigit():
                word_obj = word_by_id.get(int(word_id))
                if word_obj:
                    answer = word_obj.korean
            if answer is None and q in real_answers:
                answer = real_answers[q]

            if answer is not None and pos:
                pos_answer = services.select_meaning_by_pos(answer, pos)
                if pos_answer:
                    answer = pos_answer

            if answer is not None:
                item['korean'] = answer # 정답 주입
                
        score, wrong_count, processed_details = services.calculate_score(raw_details)
        print(
            "DEBUG submit_test scored:",
            {"score": score, "wrong_count": wrong_count, "total": len(processed_details)},
        )
        
        # 2. 결과 저장
        with transaction.atomic():
            assignment_id = data.get('assignment_id')
            result = TestResult.objects.create(
                student=profile,
                book=book,
                score=score,
                wrong_count=wrong_count,
                test_range=test_range,
                total_count=len(processed_details),
                assignment_id=assignment_id,
            )
            
            # 쿨타임 업데이트
            services.update_cooldown(profile, mode, score, total_count=len(processed_details))

            # [NEW] 3-Strike Rule 및 오답 노트 업데이트
            services.process_snowball_results(profile, processed_details)
            
            # 상세 내용 저장
            details_objs = [
                TestResultDetail(
                    result=result,
                    word_question=item['q'],
                    question_pos=item.get('pos'),  # [NEW] Save POS info
                    student_answer=item['u'],
                    correct_answer=item['a'],
                    is_correct=item['c']
                ) for item in processed_details
            ]
            TestResultDetail.objects.bulk_create(details_objs)
            
            # [NEW] Assignment Completion Logic
            is_assignment_completed = False
            # [FIX] assignment_id가 문자열(예: 'self_study_...')이면 건너뛰기
            if assignment_id and str(assignment_id).isdigit():
                try:
                    from academy.models import AssignmentTask
                    task = AssignmentTask.objects.get(id=int(assignment_id), student=profile)
                    # Pass Criteria: Score >= 90% (e.g. 27/30)
                    total_q = len(processed_details)
                    if total_q > 0 and (score / total_q) >= 0.9:
                        task.is_completed = True
                        task.completed_at = timezone.now()
                        task.save()
                        is_assignment_completed = True
                except (AssignmentTask.DoesNotExist, ValueError):
                    pass
            
        return Response({
            'score': score,
            'wrong_count': wrong_count,
            'results': processed_details,
            'test_id': result.id,
            'assignment_completed': is_assignment_completed
        })

    @action(detail=True, methods=['post'])
    def review_result(self, request, pk=None):
        """
        [NEW] 선생님 채점 결과 반영 (정정)
        - 요청 Body: { 'corrections': [ {'word_id': 'apple', 'accepted': true}, ... ] }
        """
        result = self.get_object()
        corrections = request.data.get('corrections', [])
        
        with transaction.atomic():
            changed_count = 0
            
            for item in corrections:
                word_text = item.get('word_id') # word identifier (english text)
                accepted = item.get('accepted') # true=정답인정, false=반려(오답유지)
                
                if accepted is None:
                    continue
                
                # 1. Detail 업데이트 (정답 처리)
                detail = TestResultDetail.objects.filter(result=result, word_question=word_text).first()
                if detail:
                     detail.is_resolved = True # [FIX] Mark as resolved
                     detail.is_correction_requested = False
                     if accepted and not detail.is_correct:
                         detail.is_correct = True
                         detail.save()
                         changed_count += 1
                     else:
                         if not accepted and detail.is_correct:
                             detail.is_correct = False
                             changed_count -= 1
                         detail.save() # Save resolved status even if rejected
                     
                     # 2. 오답 노트(Snowball)에서 구출
                     # [옵션 A] 정정 승인 = 채점 오류이므로 즉시 졸업(오답집중에서 제거)
                     from .models import MasterWord, PersonalWrongWord
                     try:
                         mw = MasterWord.objects.get(text=word_text)
                         pww = PersonalWrongWord.objects.get(student=result.student, master_word=mw)
                         pww.success_count = 3  # 즉시 졸업 (채점 오류 보상)
                         pww.last_correct_at = timezone.now()
                         pww.save()
                     except: pass

            # 3. 점수 재계산
            if changed_count > 0:
                result.score += changed_count
                result.wrong_count -= changed_count
                result.save()
                
            # 4. 과제 완료 처리 (정정 승인 후 통과 기준 충족 시)
            assignment_id = result.assignment_id
            if assignment_id and str(assignment_id).isdigit():
                total_q = result.total_count or result.details.count()
                if total_q > 0 and (result.score / total_q) >= 0.9:
                    try:
                        from academy.models import AssignmentTask
                        task = AssignmentTask.objects.get(
                            id=int(assignment_id),
                            student=result.student,
                        )
                        if not task.is_completed:
                            task.is_completed = True
                            task.completed_at = timezone.now()
                            task.save()
                    except (AssignmentTask.DoesNotExist, ValueError):
                        pass
            
        return Response({'status': 'reviewed', 'new_score': result.score})

    @action(detail=False, methods=['get'])
    def vulnerable(self, request):
        """취약 단어(오답노트) + 추천 단어 조회 (utils.get_vulnerable_words 활용)"""
        profile = request.user.profile
        words = utils.get_vulnerable_words(profile)
        serializer = WordSerializer(words, many=True)
        return Response(serializer.data)

    @action(detail=True, methods=['post'])
    def request_correction(self, request, pk=None):
        """
        [NEW] 학생이 정답 정정 요청
        - URL: /vocab/api/v1/tests/{id}/request_correction/
        - data: {'word': 'apple'}
        """
        test_result = self.get_object()
        word = request.data.get('word')
        
        if not word:
            return Response({'error': 'Word required'}, status=status.HTTP_400_BAD_REQUEST)
            
        # [FIX] Use filter() instead of get() to handle potential duplicates from old tests
        details = TestResultDetail.objects.filter(result=test_result, word_question=word)
        if not details.exists():
            return Response({'error': 'Detail not found'}, status=status.HTTP_404_NOT_FOUND)
            
        # Update all matching details (in case of duplicates)
        count = details.update(is_correction_requested=True)
        return Response({'status': 'requested', 'word': word, 'count': count})

class WordViewSet(viewsets.ModelViewSet):
    """
    개별 단어 관리 API (수정/삭제)
    """
    queryset = Word.objects.all()
    serializer_class = WordSerializer
    permission_classes = [permissions.IsAuthenticated]

    def perform_update(self, serializer):
        # [TODO]: 만약 단어가 바뀌면 MasterWord 링크도 갱신해야 하는가?
        # 일단은 텍스트(english/korean)만 바뀐다고 가정.
        # 향후 MasterWord가 바뀌는 로직(English 변경 시)은 복잡하므로,
        # 단순 오타 수정 정도로만 사용 권장.
        word = serializer.save()
        if word.master_word and word.korean:
            services.sync_master_meanings(word.master_word, word.korean)

class SearchWordViewSet(viewsets.ViewSet):
    """
    하이브리드 단어 검색 API
    """
    permission_classes = [permissions.IsAuthenticated]

    def list(self, request):
        query = request.query_params.get('q', '').strip()
        if not query: return Response([])
        
        results = []
        has_exact_db = False
        
        # 1. DB 검색
        db_words = Word.objects.filter(english__icontains=query).select_related('book')[:5]
        for w in db_words:
            if w.english and w.english.lower() == query.lower():
                has_exact_db = True
            results.append({
                'id': w.id,
                'english': w.english,
                'korean': w.korean,
                'from': 'db',
                'book': w.book.title
            })
            
        # 2. 외부 API 검색 (DB에 정확한 일치가 없을 때만, 혹은 항상)
        # 정확히 일치하는게 없으면 외부 검색 시도
        if not has_exact_db:
            bst_crawl = utils.crawl_daum_dic(query)
            if bst_crawl:
                # 중복 체크
                if not any(r['english'] == bst_crawl['english'] for r in results):
                    results.insert(0, {
                        'id': None,
                        'english': bst_crawl['english'],
                        'korean': bst_crawl['korean'],
                        'from': 'api',
                        'book': 'Google Translate'
                    })
                    
        return Response(results)

    @action(detail=False, methods=['post'])
    def add_personal(self, request):
        """개인 단어장에 추가"""
        english = request.data.get('english')
        korean = request.data.get('korean')
        
        if not english or not korean:
            return Response({'error': 'english and korean required'}, status=status.HTTP_400_BAD_REQUEST)
        
        # Word 객체가 없으면 만들어야 함 (개인단어장용 임시 WordBook 사용)
        # 로직이 좀 복잡하니 간단하게 처리: PersonalWrongWord는 Word ForeignKey를 요구함.
        # 따라서 "기타 단어장" 같은 곳에 Word를 먼저 만들거나 찾아야 함.
        
        system_user = request.user # 유저가 올린걸로
        personal_pub, _ = Publisher.objects.get_or_create(name="개인단어장")
        ext_book, _ = WordBook.objects.get_or_create(
            title="내 단어장",
            publisher=personal_pub,
            defaults={'uploaded_by': system_user},
        )

        master_word, _ = MasterWord.objects.get_or_create(text=english)

        word, created = Word.objects.get_or_create(
            book=ext_book,
            english=english,
            defaults={'korean': korean, 'number': 0, 'master_word': master_word},
        )
        if not created:
            updates = []
            if word.master_word_id is None:
                word.master_word = master_word
                updates.append('master_word')
            if not word.korean:
                word.korean = korean
                updates.append('korean')
            if updates:
                word.save(update_fields=updates)

        services.sync_master_meanings(master_word, korean)

        pww = PersonalWrongWord.objects.filter(
            student=request.user.profile,
            master_word=master_word
        ).first()
        if not pww:
            legacy = PersonalWrongWord.objects.filter(
                student=request.user.profile,
                word=word,
                master_word__isnull=True
            ).first()
            if legacy:
                legacy.master_word = master_word
                if legacy.word_id is None:
                    legacy.word = word
                legacy.save(update_fields=['master_word', 'word'])
            else:
                PersonalWrongWord.objects.create(
                    student=request.user.profile,
                    master_word=master_word,
                    word=word
                )
        return Response({'status': 'success'})
