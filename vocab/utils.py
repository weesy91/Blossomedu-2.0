# vocab/utils.py

import calendar, requests
from django.utils import timezone
from .models import TestResultDetail, MonthlyTestResultDetail, Word, TestResult, PersonalWrongWord
from bs4 import BeautifulSoup

def get_vulnerable_words(profile):
    """
    [수정] 오답률 높은 단어 + 학생이 직접 추가한 오답 단어 병합
    """
    
    # 1. 기존 오답 데이터 수집 (TestResultDetail)
    normal_details = TestResultDetail.objects.filter(result__student=profile)
    monthly_details = MonthlyTestResultDetail.objects.filter(result__student=profile)

    stats = {}
    def update_stats(queryset):
        for d in queryset:
            key = d.word_question.strip().lower()
            if key not in stats: stats[key] = {'total': 0, 'wrong': 0}
            stats[key]['total'] += 1
            if not d.is_correct: stats[key]['wrong'] += 1

    update_stats(normal_details)
    update_stats(monthly_details)

    # 오답률 25% 이상인 단어 스펠링
    vulnerable_keys = {text for text, data in stats.items() if data['total'] > 0 and (data['wrong'] / data['total'] >= 0.25)}

    # -------------------------------------------------------------
    # [NEW] 2. 학생이 직접 추가한 오답 단어 가져오기
    # -------------------------------------------------------------
    personal_wrongs = PersonalWrongWord.objects.filter(student=profile).select_related('word')
    for pw in personal_wrongs:
        clean_word = pw.word.english.strip().lower()
        vulnerable_keys.add(clean_word) # 집합에 추가 (중복 자동 제거)
    
    if not vulnerable_keys:
        return []

    # 3. DB에서 후보 단어 가져오기 (english__in)
    # (주의: 스펠링이 같아도 서로 다른 책에 있는 단어가 여러 개일 수 있음)
    candidates = Word.objects.filter(english__in=vulnerable_keys).select_related('book')

    # 4. [정렬] 최근 본 책 우선 (기존 로직 유지)
    recent_tests = TestResult.objects.filter(student=profile).order_by('-created_at').values_list('book_id', flat=True)[:20]
    recent_book_ids = list(dict.fromkeys(recent_tests))

    def get_priority(word):
        if word.book_id in recent_book_ids:
            return recent_book_ids.index(word.book_id)
        return 9999

    sorted_candidates = sorted(candidates, key=get_priority)

    # 5. [중복 제거]
    unique_words = []
    seen_english = set()

    for w in sorted_candidates:
        clean_eng = w.english.strip().lower()
        if clean_eng not in seen_english:
            unique_words.append(w)
            seen_english.add(clean_eng)
    
    return unique_words

def is_monthly_test_period():
    """월말 평가 기간인지 확인 (매달 말일 7일 전부터)"""
    now = timezone.now()
    last_day = calendar.monthrange(now.year, now.month)[1]
    return now.day > (last_day - 8)

def crawl_daum_dic(query):
    """
    다음 어학사전에서 단어의 뜻을 검색하여 반환합니다.
    """
    try:
        url = f"https://dic.daum.net/search.do?q={query}"
        headers = {'User-Agent': 'Mozilla/5.0'}
        response = requests.get(url, headers=headers, timeout=3)
        
        if response.status_code != 200:
            return None
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 검색 결과 중 '단어' 영역 파싱 (첫 번째 결과만)
        # (사이트 구조 변경에 따라 선택자는 바뀔 수 있음)
        search_box = soup.select_one('.search_box')
        if not search_box:
            return None
            
        # 단어 (영어)
        word_eng = search_box.select_one('.txt_clebsch')
        if not word_eng:
            return None
        english = word_eng.text.strip()
        
        # 뜻 (여러 개일 경우 콤마로 연결)
        meanings = search_box.select('.txt_search')
        korean_list = [m.text.strip() for m in meanings]
        korean = ", ".join(korean_list)
        
        if not english or not korean:
            return None
            
        return {
            'english': english,
            'korean': korean,
            'source': 'external'
        }
        
    except Exception as e:
        print(f"Crawler Error: {e}")
        return None