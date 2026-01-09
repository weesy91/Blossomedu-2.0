import requests
from bs4 import BeautifulSoup
from django.utils import timezone
from .models import TestResultDetail, MonthlyTestResultDetail, Word, TestResult, PersonalWrongWord

def get_vulnerable_words(profile):
    """
    [수정] 오답률 높은 단어 + 학생이 직접 추가한 오답 단어 병합
    (기존 코드 유지)
    """
    # 1. 기존 오답 데이터 수집
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

    vulnerable_keys = {text for text, data in stats.items() if data['total'] > 0 and (data['wrong'] / data['total'] >= 0.25)}

    # 2. 학생 추가 오답
    personal_wrongs = PersonalWrongWord.objects.filter(student=profile).select_related('word')
    for pw in personal_wrongs:
        clean_word = pw.word.english.strip().lower()
        vulnerable_keys.add(clean_word)
    
    if not vulnerable_keys:
        return []

    # 3. DB 조회
    candidates = Word.objects.filter(english__in=vulnerable_keys).select_related('book')

    # 4. 정렬
    recent_tests = TestResult.objects.filter(student=profile).order_by('-created_at').values_list('book_id', flat=True)[:20]
    recent_book_ids = list(dict.fromkeys(recent_tests))

    def get_priority(word):
        if word.book_id in recent_book_ids:
            return recent_book_ids.index(word.book_id)
        return 9999

    sorted_candidates = sorted(candidates, key=get_priority)

    # 5. 중복 제거
    unique_words = []
    seen_english = set()

    for w in sorted_candidates:
        clean_eng = w.english.strip().lower()
        if clean_eng not in seen_english:
            unique_words.append(w)
            seen_english.add(clean_eng)
    
    return unique_words

def is_monthly_test_period():
    now = timezone.now()
    import calendar
    last_day = calendar.monthrange(now.year, now.month)[1]
    return now.day > (last_day - 8)

def crawl_daum_dic(query):
    """
    다음 어학사전 (모바일 버전) 크롤링
    모바일 페이지(m.dic.daum.net)가 구조가 단순하여 성공률이 높습니다.
    """
    print(f"--- [DEBUG] 모바일 크롤링 시작: {query} ---")
    try:
        # 모바일 URL 사용
        url = f"https://m.dic.daum.net/search.do?q={query}&dic=eng"
        headers = {
            # 모바일(iPhone) User-Agent 사용
            'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1'
        }
        
        response = requests.get(url, headers=headers, timeout=5)
        
        if response.status_code != 200:
            print(f"--- [DEBUG] 응답 오류: {response.status_code} ---")
            return None
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # 1. 단어 찾기 (모바일 구조)
        # 상세 페이지의 제목(.tit_word) 혹은 검색 목록의 제목(.txt_clebsch)
        word_element = soup.select_one('.tit_word')
        if not word_element:
            word_element = soup.select_one('.txt_clebsch')
            
        if not word_element:
            # 그래도 없으면 HTML 구조가 완전히 다른 경우이므로 디버깅을 위해 일부 출력
            print(f"--- [DEBUG] 단어 요소 찾기 실패. HTML 앞부분: {soup.text[:100]} ---")
            return None
            
        english = word_element.text.strip()
        
        # 2. 뜻 찾기 (모바일 구조)
        # 상세 페이지 뜻(.list_mean .txt_mean) 혹은 검색 목록 뜻(.list_search .txt_search)
        meanings_list = soup.select('.list_mean .txt_mean')
        if not meanings_list:
            meanings_list = soup.select('.list_search .txt_search')
            
        if not meanings_list:
            print("--- [DEBUG] 뜻 목록을 찾을 수 없음 ---")
            return None
            
        # 상위 3개 뜻만 추출
        korean_list = [m.text.strip() for m in meanings_list[:3]]
        korean = ", ".join(korean_list)
        
        print(f"--- [DEBUG] 크롤링 성공: {english} -> {korean} ---")
        
        return {
            'english': english,
            'korean': korean,
            'source': 'external'
        }
        
    except Exception as e:
        print(f"--- [DEBUG] 크롤링 예외 발생: {e} ---")
        return None