import requests
from bs4 import BeautifulSoup
from django.utils import timezone
from .models import TestResultDetail, MonthlyTestResultDetail, Word, TestResult, PersonalWrongWord

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

    # 2. 학생이 직접 추가한 오답 단어 가져오기
    personal_wrongs = PersonalWrongWord.objects.filter(student=profile).select_related('word')
    for pw in personal_wrongs:
        clean_word = pw.word.english.strip().lower()
        vulnerable_keys.add(clean_word)
    
    if not vulnerable_keys:
        return []

    # 3. DB에서 후보 단어 가져오기
    candidates = Word.objects.filter(english__in=vulnerable_keys).select_related('book')

    # 4. [정렬] 최근 본 책 우선
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
    import calendar
    now = timezone.now()
    last_day = calendar.monthrange(now.year, now.month)[1]
    return now.day > (last_day - 8)

def crawl_daum_dic(query):
    """
    다음 어학사전 크롤링 (상세 페이지 리다이렉트 대응 버전)
    """
    print(f"--- [DEBUG] 크롤링 시작: {query} ---")
    try:
        url = f"https://dic.daum.net/search.do?q={query}&dic=eng"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
        }
        # allow_redirects=True (기본값) 덕분에 상세 페이지로 넘어가면 그 HTML을 가져옴
        response = requests.get(url, headers=headers, timeout=5)
        
        if response.status_code != 200:
            print(f"--- [DEBUG] 응답 오류: {response.status_code} ---")
            return None
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # ---------------------------------------------------
        # [Strategy A] 검색 결과 목록 페이지 (search.do) 구조
        # ---------------------------------------------------
        word_element = soup.select_one('.txt_clebsch')
        if not word_element:
            word_element = soup.select_one('.tit_clebsch')
            
        if word_element:
            # 목록 페이지에서 찾음
            english = word_element.text.strip()
            meanings_list = soup.select('.list_search .txt_search')
            if not meanings_list:
                meanings_list = soup.select('.list_mean .txt_mean')
        
        # ---------------------------------------------------
        # [Strategy B] 단어 상세 페이지 (word/view.do) 구조
        # (리다이렉트 되었을 경우 이 구조를 가짐)
        # ---------------------------------------------------
        else:
            print("--- [DEBUG] 목록 구조 없음, 상세 페이지 구조 탐색 ---")
            # 상세 페이지의 단어 타이틀
            word_element = soup.select_one('.tit_word .txt_word')
            
            if word_element:
                english = word_element.text.strip()
                # 상세 페이지의 뜻 목록
                meanings_list = soup.select('.list_mean .txt_mean')
            else:
                print("--- [DEBUG] 상세 페이지 구조도 찾을 수 없음 (크롤링 실패) ---")
                return None

        # --- 결과 정리 ---
        if not meanings_list:
            print("--- [DEBUG] 뜻을 찾을 수 없음 ---")
            return None
            
        # 상위 3개 뜻만
        korean_list = [m.text.strip() for m in meanings_list[:3]]
        korean = ", ".join(korean_list)
        
        # 검색어와 결과가 너무 다르면(다른 단어 검색됨) 필터링 할 수도 있으나,
        # 일단은 가져온 것을 신뢰
        
        print(f"--- [DEBUG] 크롤링 성공: {english} -> {korean} ---")
        
        return {
            'english': english,
            'korean': korean,
            'source': 'external'
        }
        
    except Exception as e:
        print(f"--- [DEBUG] 크롤링 예외 발생: {e} ---")
        return None