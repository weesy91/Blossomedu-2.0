import json
import random
import calendar
from datetime import timedelta
from django.shortcuts import render, get_object_or_404, redirect
from django.http import JsonResponse, HttpResponse
from django.views.decorators.csrf import csrf_exempt
from django.contrib.auth.decorators import login_required
from django.db.models import Q, Count, F 
from django.db.models.functions import TruncDate
from django.db import transaction
from django.utils import timezone
from django.contrib.admin.views.decorators import staff_member_required

from .models import WordBook, Word, TestResult, TestResultDetail, MonthlyTestResult, MonthlyTestResultDetail, Publisher
from core.models import StudentProfile

# ==========================================
# [보조 함수] 오답률 높은 취약 단어 추출
# ==========================================
def get_vulnerable_words(user):
    # 1. 모든 상세 기록 가져오기
    normal_details = TestResultDetail.objects.filter(result__student=user)
    monthly_details = MonthlyTestResultDetail.objects.filter(result__student=user)

    # 2. 통계 계산
    stats = {}
    def update_stats(queryset):
        for d in queryset:
            key = d.word_question.strip().lower()
            if key not in stats: stats[key] = {'total': 0, 'wrong': 0}
            stats[key]['total'] += 1
            if not d.is_correct: stats[key]['wrong'] += 1

    update_stats(normal_details)
    update_stats(monthly_details)

    vulnerable_keys = {text for text, data in stats.items() if data['total'] > 0 and (data['wrong'] / data['total'] >= 0.25)}

    all_words = Word.objects.all()
    unique_vulnerable_list = []
    seen_texts = set()

    for w in all_words:
        clean_text = w.english.strip().lower()
        if clean_text in vulnerable_keys:
            if clean_text not in seen_texts:
                unique_vulnerable_list.append(w)
                seen_texts.add(clean_text)

    return unique_vulnerable_list

def is_monthly_test_period():
    
     now = timezone.now()
     last_day = calendar.monthrange(now.year, now.month)[1]
     return now.day > (last_day - 8)

# ==========================================
# [View] 메인 화면
# ==========================================
@login_required(login_url='core:login')
def index(request):
    publishers = Publisher.objects.all().order_by('name')
    etc_books = WordBook.objects.filter(publisher__isnull=True).order_by('-created_at')
    wrong_words = get_vulnerable_words(request.user)
    
    # ---------------------------------------------------------
    # 1. [성장 그래프] 최근 10번의 시험 점수 가져오기
    # ---------------------------------------------------------
    recent_tests = TestResult.objects.filter(student=request.user).order_by('-created_at')[:10]
    recent_tests = reversed(list(recent_tests))
    
    graph_labels = []
    graph_data = [] 
    
    for t in recent_tests:
        graph_labels.append(t.created_at.strftime('%m/%d'))
        graph_data.append(t.score)

    # ---------------------------------------------------------
    # 2. [명예의 전당] 이번 달 랭킹 (학교명 추가)
    # ---------------------------------------------------------
    now = timezone.now()
    # [월말 초기화 자동 적용] 매달 1일 0시 0분 0초를 시작점으로 잡습니다.
    start_of_month = now.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
    
    # A. 이번 달의 '모든' 기록 가져오기
    raw_records = TestResult.objects.filter(
        created_at__gte=start_of_month
    ).select_related('student', 'student__profile', 'student__profile__school', 'book').order_by('created_at')
    
    # B. 학생별 점수 계산
    student_scores = {}
    
    for r in raw_records:
        sid = r.student.id
        
        # [수정] 이름 + (학교명) 조합하기
        if hasattr(r.student, 'profile'):
            name = r.student.profile.name
            school_name = r.student.profile.school.name if r.student.profile.school else "학교미정"
            display_name = f"{name} ({school_name})"
        else:
            display_name = f"{r.student.username} (정보없음)"

        range_key = f"{r.book.id}_{r.test_range}"
        
        if sid not in student_scores:
            student_scores[sid] = {'name': display_name, 'ranges': {}}
            
        # 해당 범위의 '최신 점수'로 갱신
        student_scores[sid]['ranges'][range_key] = r.score
            
    # C. 총점(XP) 계산 (27점 이상만 합산)
    final_ranking = []
    for sid, data in student_scores.items():
        valid_scores = [s for s in data['ranges'].values() if s >= 27]
        total_xp = sum(valid_scores)
        
        # [옵션] 0점인 학생은 랭킹에서 뺄까요? 
        # 일단은 0점이라도 이름을 보여주기 위해 조건 없이 추가합니다.
        # 만약 점수 있는 학생만 보고 싶으시면 'if total_xp > 0:' 조건을 넣으세요.
        final_ranking.append({
            'name': data['name'],
            'count': total_xp
        })
        
    # D. 랭킹 정렬 (점수 높은 순)
    final_ranking.sort(key=lambda x: x['count'], reverse=True)
    
    ranking_list = []
    for i, item in enumerate(final_ranking[:5], 1): # TOP 5만 표시
        item['rank'] = i
        ranking_list.append(item)

    return render(request, 'vocab/index.html', {
        'publishers': publishers,
        'etc_books': etc_books,
        'is_monthly_period': is_monthly_test_period(),
        'is_wrong_mode_active': len(wrong_words) >= 30, 
        'wrong_count': len(wrong_words),
        'graph_labels': json.dumps(graph_labels),
        'graph_data': json.dumps(graph_data),
        'ranking_list': ranking_list,
    })

# ==========================================
# [View] 시험 페이지 (Exam)
# ==========================================
@login_required(login_url='core:login')
def exam(request):
    mode = request.GET.get('mode', 'practice')
    
    is_monthly = (mode == 'monthly')
    is_challenge = (mode == 'challenge')
    is_wrong_mode = (mode == 'wrong')
    is_practice = (mode == 'practice')
    is_learning = (mode == 'learning')

    profile, _ = StudentProfile.objects.get_or_create(user=request.user)

    # 1. [월말평가] 응시 기회 체크
    if is_monthly:
        now = timezone.now()
        already_taken = MonthlyTestResult.objects.filter(
            student=request.user,
            created_at__year=now.year,
            created_at__month=now.month
        ).exists()
        
        if already_taken:
            return HttpResponse(f"<script>alert('🚫 월말평가는 이번 달에 이미 응시하셨습니다.\\n(중도 포기한 경우도 재응시 불가)');window.location.href='/vocab/';</script>")

    # 2. [도전/오답] 쿨타임 체크
    if is_challenge:
        if profile.last_failed_at:
            time_passed = timezone.now() - profile.last_failed_at
            if time_passed < timedelta(minutes=5):
                remaining = 5 - (time_passed.seconds // 60)
                return HttpResponse(f"<script>alert('🔥 쿨타임 중입니다. ({remaining}분 남음)');window.location.href='/vocab/';</script>")
    elif is_wrong_mode:
        if profile.last_wrong_failed_at:
            time_passed = timezone.now() - profile.last_wrong_failed_at
            if time_passed < timedelta(minutes=5):
                remaining = 5 - (time_passed.seconds // 60)
                return HttpResponse(f"<script>alert('🚨 오답모드 쿨타임 중입니다. ({remaining}분 남음)');window.location.href='/vocab/';</script>")

    # 3. 단어 데이터 준비
    raw_candidates = []
    book_title = ""
    book_id = request.GET.get('book_id') # 여기서 미리 받음
    test_range_str = ""
    real_book = None

    if is_wrong_mode:
        raw_candidates = get_vulnerable_words(request.user)
        if len(raw_candidates) < 1: return redirect('vocab:index') 
        book_title = "🚨 오답 탈출"
        book_id = "wrong_mode"
        test_range_str = "오답집중"
        real_book = WordBook.objects.first() 
    else:
        # [수정] 월말평가라도 단어장(book_id)이 있으면 범위를 따릅니다!
        if book_id:
            real_book = get_object_or_404(WordBook, id=book_id)
            book_title = real_book.title
            
            # 월말평가면 타이틀에 표시 추가
            if is_monthly: book_title = f"[월말] {book_title}"

            test_range_str = request.GET.get('day_range', '전체')
            
            target_days = []
            try:
                if test_range_str and test_range_str != '전체':
                    for chunk in test_range_str.split(','):
                        if '-' in chunk:
                            s, e = map(int, chunk.split('-'))
                            target_days.extend(range(s, e + 1))
                        else:
                            target_days.append(int(chunk))
            except: target_days = []

            if target_days:
                raw_candidates = list(Word.objects.filter(book=real_book, number__in=target_days))
            else:
                raw_candidates = list(Word.objects.filter(book=real_book))
        
        else:
            # 단어장 선택 안 함 + 월말평가 = 진짜 전체 범위 (기존 로직 유지)
            if is_monthly:
                raw_candidates = list(Word.objects.all())
                book_title = "📅 전체 월말 평가"
                test_range_str = "전범위"
                real_book = WordBook.objects.first()
            else:
                # 일반 모드인데 책 선택 안 했으면 튕겨냄
                return redirect('vocab:index')

    # 중복 제거 및 랜덤 추출
    random.shuffle(raw_candidates)
    words = []
    seen_english = set()
    target_count = 100 if is_monthly else 30
    if is_learning: target_count = 999999

    for w in raw_candidates:
        key = w.english.strip().lower()
        if key not in seen_english:
            words.append(w)
            seen_english.add(key)
        if len(words) >= target_count: break

    # 4. 빈 성적표 생성
    pre_saved_id = None
    if not is_practice and not is_learning:
        if is_monthly:
            result = MonthlyTestResult.objects.create(student=request.user, book=real_book, score=0, total_questions=len(words), test_range=test_range_str)
        else:
            result = TestResult.objects.create(student=request.user, book=real_book, score=0, total_count=len(words), wrong_count=len(words), test_range=test_range_str)
            if is_challenge: profile.last_failed_at = timezone.now()
            elif is_wrong_mode: profile.last_wrong_failed_at = timezone.now()
            profile.save()
            
        pre_saved_id = result.id

    word_list = [{'english': w.english, 'korean': w.korean, 'example': w.example_sentence or "", 'day': w.number} for w in words]

    return render(request, 'vocab/exam.html', {
        'words_json': word_list,
        'mode': mode,
        'book_title': book_title,
        'test_id': pre_saved_id,
        'is_practice': is_practice,
        'is_monthly': is_monthly,
        'is_wrong_mode': is_wrong_mode,
        'is_learning': is_learning,
    })

# ==========================================
# [API] 결과 저장 (중복 방지 강화)
# ==========================================
@csrf_exempt
def save_result(request):
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            mode = data.get('mode')
            if mode == 'practice': return JsonResponse({'status': 'success'})

            user = request.user
            test_id = data.get('test_id')
            is_monthly = (mode == 'monthly')
            
            # [핵심 수정 1] 서버 사이드 재채점 (띄어쓰기 무시)
            # 프론트엔드 점수를 무시하고, 서버 기준에서 다시 계산합니다.
            recalculated_score = 0
            recalculated_wrong_count = 0
            
            for item in data.get('details', []):
                # 공백을 모두 제거하고 비교
                user_clean = item.get('user_input', '').replace(" ", "").strip()
                ans_clean = item.get('korean', '').replace(" ", "").strip()
                
                # 내용이 같으면 정답으로 강제 변경
                if user_clean == ans_clean:
                    item['is_correct'] = True
                
                # 점수 카운트
                if item.get('is_correct', False):
                    recalculated_score += 1
                else:
                    recalculated_wrong_count += 1
            
            # 재계산된 점수 적용
            score = recalculated_score
            wrong_count = recalculated_wrong_count

            with transaction.atomic():
                if is_monthly:
                    result = get_object_or_404(MonthlyTestResult, id=test_id, student=user)
                    
                    if MonthlyTestResultDetail.objects.filter(result=result).exists():
                        return JsonResponse({'status': 'success', 'message': 'Duplicate skipped'})
                    
                    result.score = score # 재계산된 점수 저장
                    result.save()
                    ModelDetail = MonthlyTestResultDetail
                else:
                    result = get_object_or_404(TestResult, id=test_id, student=user)
                    
                    if TestResultDetail.objects.filter(result=result).exists():
                         return JsonResponse({'status': 'success', 'message': 'Duplicate skipped'})

                    result.score = score # 재계산된 점수 저장
                    result.wrong_count = wrong_count # 재계산된 오답 수 저장
                    result.save()
                    ModelDetail = TestResultDetail
                    
                    # 쿨타임 처리
                    profile, _ = StudentProfile.objects.get_or_create(user=user)
                    PASS_SCORE = 27
                    if mode == 'challenge':
                        if score >= PASS_SCORE: profile.last_failed_at = None
                        else: profile.last_failed_at = timezone.now()
                    elif mode == 'wrong':
                        if score >= PASS_SCORE: profile.last_wrong_failed_at = None
                        else: profile.last_wrong_failed_at = timezone.now()
                    profile.save()

                details = [
                    ModelDetail(
                        result=result, 
                        word_question=item.get('english', ''), 
                        student_answer=item.get('user_input', ''), 
                        correct_answer=item.get('korean', ''), 
                        is_correct=item.get('is_correct', False)
                    ) 
                    for item in data.get('details', [])
                ]
                ModelDetail.objects.bulk_create(details)
                
                if is_monthly:
                    saved_ids = list(MonthlyTestResultDetail.objects.filter(result=result).values_list('id', flat=True))
                else:
                    saved_ids = list(TestResultDetail.objects.filter(result=result).values_list('id', flat=True))
            
            return JsonResponse({'status': 'success', 'detail_ids': saved_ids})
        except Exception as e:
            return JsonResponse({'status': 'error', 'message': str(e)})
    return JsonResponse({'status': 'error'})
# ==========================================
# [View] 오답 학습 화면 (누락되었던 부분 복구!)
# ==========================================
@login_required
def wrong_answer_study(request):
    vulnerable_words = get_vulnerable_words(request.user)
    return render(request, 'vocab/wrong_study.html', {'words': vulnerable_words, 'count': len(vulnerable_words)})

# ==========================================
# [API] 정답 정정 요청 (누락되었던 부분 복구!)
# ==========================================
@csrf_exempt
@login_required
def request_correction(request):
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            detail_id = data.get('detail_id')
            is_monthly = data.get('is_monthly', False)
            if is_monthly: detail = get_object_or_404(MonthlyTestResultDetail, id=detail_id)
            else: detail = get_object_or_404(TestResultDetail, id=detail_id)

            if detail.result.student != request.user: return JsonResponse({'status': 'error', 'message': '권한 없음'})

            detail.is_correction_requested = True
            detail.is_resolved = False
            detail.save()
            return JsonResponse({'status': 'success'})
        except Exception as e: return JsonResponse({'status': 'error', 'message': str(e)})
    return JsonResponse({'status': 'error'})

# ==========================================
# [Admin View] 결과 목록 리스트 (누락되었던 부분 복구!)
# ==========================================
@login_required
def test_result_list(request):
    if not request.user.is_staff: return redirect('vocab:index')
    results = TestResult.objects.all().order_by('-created_at')
    return render(request, 'vocab/admin_result_list.html', {'results': results})

# ==========================================
# [Admin View] 상세 결과
# ==========================================
@login_required
def test_result_detail(request, result_id):
    """일반/도전 모드용 상세 보기"""
    result = get_object_or_404(TestResult, id=result_id)
    try: details = result.details.all().order_by('id')
    except AttributeError: details = result.testresultdetail_set.all().order_by('id')
    return render(request, 'vocab/admin_result_detail.html', {'result': result, 'details': details})

# ==========================================
# [API] 정답 인정 (월말 평가 지원 추가)
# ==========================================
@csrf_exempt
@login_required
def approve_answer(request):
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            detail_id = data.get('detail_id')
            
            is_monthly_detail = False
            detail = None
            
            try:
                detail = TestResultDetail.objects.select_for_update().get(id=detail_id)
            except TestResultDetail.DoesNotExist:
                try:
                    detail = MonthlyTestResultDetail.objects.select_for_update().get(id=detail_id)
                    is_monthly_detail = True
                except MonthlyTestResultDetail.DoesNotExist:
                    return JsonResponse({'status': 'error', 'message': '존재하지 않는 답안 ID'})

            with transaction.atomic():
                result = detail.result
                if detail.is_correct:
                    return JsonResponse({'status': 'already_correct'})

                detail.is_correct = True
                detail.is_resolved = True
                detail.save()

                # 점수 재계산
                if is_monthly_detail:
                    result = MonthlyTestResult.objects.select_for_update().get(id=result.id)
                    real_score = MonthlyTestResultDetail.objects.filter(result=result, is_correct=True).count()
                    result.score = real_score
                    result.save()
                else:
                    result = TestResult.objects.select_for_update().get(id=result.id)
                    real_score = TestResultDetail.objects.filter(result=result, is_correct=True).count()
                    total_count = TestResultDetail.objects.filter(result=result).count()
                    result.score = real_score
                    result.wrong_count = total_count - real_score
                    result.save()
                    
                    if result.score >= 27:
                        profile = result.student.profile
                        if result.test_range == "오답집중": profile.last_wrong_failed_at = None
                        else: profile.last_failed_at = None
                        profile.save()
            
            return JsonResponse({'status': 'success', 'new_score': result.score})
        except Exception as e:
            return JsonResponse({'status': 'error', 'message': str(e)})
    return JsonResponse({'status': 'error'})

# ==========================================
# [New] 작심 30일 챌린지 관리자 확인 페이지
# ==========================================
@staff_member_required # 관리자만 접속 가능
def admin_event_check(request):
    """
    최근 30일 동안 '하루에 한 번이라도 통과(27점↑)'한 날짜가 많은 학생 찾기
    """
    # 기준: 오늘 포함 최근 30일
    today = timezone.now().date()
    start_date = today - timedelta(days=29) # 30일 전

    # 1. 기간 내 통과 기록 가져오기
    pass_records = TestResult.objects.filter(
        created_at__date__gte=start_date,
        score__gte=27
    ).annotate(
        exam_date=TruncDate('created_at') # 날짜별로 자르기 (하루에 여러번 봐도 1번으로 치기 위해)
    ).values(
        'student__id', 'student__username', 'student__profile__name', 'exam_date'
    ).distinct() # (학생, 날짜) 중복 제거 -> 즉, 출석 일수만 남음

    # 2. 학생별 출석 일수 카운트
    student_stats = {}
    for record in pass_records:
        uid = record['student__id']
        name = record['student__profile__name'] or record['student__username']
        
        if uid not in student_stats:
            student_stats[uid] = {'name': name, 'days': 0, 'dates': []}
        
        student_stats[uid]['days'] += 1
        student_stats[uid]['dates'].append(record['exam_date'])

    # 3. 리스트로 변환 및 정렬 (출석일수 많은 순)
    result_list = []
    for uid, data in student_stats.items():
        # [조건] 최소 1일 이상 통과한 학생만 표시 (원하면 20일, 30일 등으로 필터링 가능)
        result_list.append({
            'name': data['name'],
            'days': data['days'],
            'success_rate': round((data['days'] / 30) * 100, 1)
        })
    
    result_list.sort(key=lambda x: x['days'], reverse=True)

    return render(request, 'vocab/admin_event_check.html', {
        'challengers': result_list,
        'total_days': 30
    })

# vocab/views.py

# ... (기존 imports 유지) ...

# ==========================================
# [1] 선생님용 채점 목록 (시험지 단위 그룹핑)
# ==========================================
@staff_member_required
def grading_list(request):
    """
    정정 요청이 있는 시험지들을 모아서 보여줍니다.
    [기능] 이름순 / 최신순 정렬 지원
    """
    sort_by = request.GET.get('sort', 'date') # 'date' or 'name'

    # 1. 일반/도전 모드에서 요청 있는 시험지 찾기
    pending_tests = TestResult.objects.filter(
        details__is_correction_requested=True, 
        details__is_resolved=False
    ).distinct().select_related('student', 'student__profile', 'book')

    # 2. 월말 평가에서 요청 있는 시험지 찾기
    pending_monthly = MonthlyTestResult.objects.filter(
        details__is_correction_requested=True, 
        details__is_resolved=False
    ).distinct().select_related('student', 'student__profile', 'book')

    # 3. 데이터 통합 리스트 만들기
    exam_list = []

    def add_to_list(queryset, q_type):
        for exam in queryset:
            # 요청 건수 세기
            req_count = exam.details.filter(is_correction_requested=True, is_resolved=False).count()
            
            # 학생 이름 확인
            if hasattr(exam.student, 'profile'):
                s_name = exam.student.profile.name
            else:
                s_name = exam.student.username

            exam_list.append({
                'id': exam.id,
                'type': q_type, # 'normal' or 'monthly'
                'student_name': s_name,
                'book_title': exam.book.title,
                'test_range': exam.test_range,
                'score': exam.score,
                'pending_count': req_count,
                'created_at': exam.created_at,
            })

    add_to_list(pending_tests, 'normal')
    add_to_list(pending_monthly, 'monthly')

    # 4. 정렬 로직
    if sort_by == 'name':
        exam_list.sort(key=lambda x: x['student_name'])
    else: # date (최신순)
        exam_list.sort(key=lambda x: x['created_at'], reverse=True)

    return render(request, 'vocab/grading_list.html', {
        'exam_list': exam_list,
        'current_sort': sort_by
    })


# ==========================================
# [2] 시험지 상세 (30단어 표 화면)
# ==========================================
@staff_member_required
def grading_detail(request, test_type, result_id):
    """
    선택한 시험지의 30개 단어 전체를 표로 보여줍니다.
    """
    if test_type == 'monthly':
        exam = get_object_or_404(MonthlyTestResult, id=result_id)
        details = exam.details.all().order_by('id') 
    else:
        exam = get_object_or_404(TestResult, id=result_id)
        details = exam.details.all().order_by('id')

    # 학생 이름
    student_name = exam.student.profile.name if hasattr(exam.student, 'profile') else exam.student.username

    return render(request, 'vocab/grading_detail.html', {
        'exam': exam,
        'details': details,
        'test_type': test_type,
        'student_name': student_name,
    })


# ==========================================
# [3] 정답 기각 (API)
# ==========================================
@csrf_exempt
@login_required
def reject_answer(request):
    """
    선생님이 요청을 거절함 -> 상태만 '처리됨'으로 변경 (점수 변동 X)
    """
    if request.method == 'POST':
        try:
            data = json.loads(request.body)
            detail_id = data.get('detail_id')
            q_type = data.get('type') # 'normal' or 'monthly'
            
            if q_type == 'monthly':
                detail = get_object_or_404(MonthlyTestResultDetail, id=detail_id)
            else:
                detail = get_object_or_404(TestResultDetail, id=detail_id)

            # 상태 업데이트
            detail.is_resolved = True 
            detail.is_correction_requested = False 
            detail.save()
            
            return JsonResponse({'status': 'success'})
        except Exception as e:
            return JsonResponse({'status': 'error', 'message': str(e)})
    return JsonResponse({'status': 'error'})
