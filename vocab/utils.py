import requests
from django.utils import timezone
from .models import TestResultDetail, MonthlyTestResultDetail, Word, TestResult, PersonalWrongWord

# ==============================================================================
# [1] 기존 로직 유지
# ==============================================================================
def get_vulnerable_words(profile):
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

    personal_wrongs = PersonalWrongWord.objects.filter(student=profile).select_related('word')
    for pw in personal_wrongs:
        vulnerable_keys.add(pw.word.english.strip().lower())
    
    if not vulnerable_keys:
        return []

    candidates = Word.objects.filter(english__in=vulnerable_keys).select_related('book')

    recent_tests = TestResult.objects.filter(student=profile).order_by('-created_at').values_list('book_id', flat=True)[:20]
    recent_book_ids = list(dict.fromkeys(recent_tests))

    def get_priority(word):
        if word.book_id in recent_book_ids:
            return recent_book_ids.index(word.book_id)
        return 9999

    sorted_candidates = sorted(candidates, key=get_priority)

    unique_words = []
    seen_english = set()

    for w in sorted_candidates:
        clean_eng = w.english.strip().lower()
        if clean_eng not in seen_english:
            unique_words.append(w)
            seen_english.add(clean_eng)
    
    return unique_words

def is_monthly_test_period():
    import calendar
    now = timezone.now()
    last_day = calendar.monthrange(now.year, now.month)[1]
    return now.day > (last_day - 8)

# ==============================================================================
# [2] 외부 사전 검색 (구글 번역 API 활용) - 차단 우회용
# ==============================================================================
def crawl_daum_dic(query):
    """
    [최종 해결] 구글 번역(Google Translate) API 활용
    - 네이버/다음의 IP 차단을 피하기 위해 구글 사용
    - JSON 응답으로 안정적이고 빠름
    """
    print(f"--- [DEBUG] 구글 번역 API 요청: {query} ---")
    try:
        # 구글 번역 API URL (비공식 endpoint지만 매우 안정적)
        url = "https://translate.googleapis.com/translate_a/single"
        params = {
            "client": "gtx", # Google Translate Extension
            "sl": "en",      # Source Language (영어)
            "tl": "ko",      # Target Language (한국어)
            "dt": "t",       # Return type (Translation)
            "q": query       # 검색어
        }
        
        response = requests.get(url, params=params, timeout=5)
        
        if response.status_code != 200:
            print(f"--- [DEBUG] 응답 오류: {response.status_code} ---")
            return None
        
        # JSON 파싱
        data = response.json()
        
        # 데이터 구조: [[["사과","apple",null,null,1]], ... ]
        if not data or not data[0] or not data[0][0]:
            print("--- [DEBUG] 번역 결과 없음 ---")
            return None
            
        # 첫 번째 번역 결과 가져오기
        korean = data[0][0][0]
        english = query 
        
        print(f"--- [DEBUG] 번역 성공: {english} -> {korean} ---")
        
        return {
            'english': english,
            'korean': korean,
            'source': 'google_translate'
        }
        
    except Exception as e:
        print(f"--- [DEBUG] 예외 발생: {e} ---")
        return None