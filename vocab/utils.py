import requests
from bs4 import BeautifulSoup
from django.utils import timezone
from .models import TestResultDetail, MonthlyTestResultDetail

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
    # (PersonalWrongWord 모델은 views.py 등에서 import 되거나, models가 순환 참조되지 않도록 주의)
    # 여기서는 간단히 user -> personal_wrong_words 역참조 사용
    personal_wrongs = profile.personal_wrong_words.select_related('word').all()
    for pw in personal_wrongs:
        vulnerable_keys.add(pw.word.english.strip().lower())

    # 3. 실제 Word 객체 조회 (한 번에 가져오기)
    from .models import Word  # 함수 내부 import로 순환 참조 방지
    final_words = Word.objects.filter(english__in=vulnerable_keys).distinct()
    
    return list(final_words)

def is_monthly_test_period():
    """월말 평가 기간인지 확인 (매달 말일 7일 전부터)"""
    import calendar # 내부 import
    now = timezone.now()
    last_day = calendar.monthrange(now.year, now.month)[1]
    return now.day > (last_day - 8)

def crawl_daum_dic(query):
    """
    다음 어학사전에서 단어의 뜻을 검색하여 반환합니다. (개선된 버전)
    """
    print(f"--- [DEBUG] 크롤링 시작: {query} ---") # 로그 추가
    try:
        # dic=eng 파라미터를 추가하여 '영어사전' 결과만 우선 조회
        url = f"https://dic.daum.net/search.do?q={query}&dic=eng"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        response = requests.get(url, headers=headers, timeout=5)
        
        if response.status_code != 200:
            print(f"--- [DEBUG] 응답 오류: {response.status_code} ---")
            return None
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # [수정된 선택자]
        # 1. 가장 정확한 단어 카드 영역 찾기 (class="cleanword_type")
        search_result = soup.select_one('.cleanword_type')
        
        # 만약 cleanword_type이 없으면 다른 구조(card_word) 시도
        if not search_result:
            search_result = soup.select_one('.card_word[data-tiara-layer="word eng"]')

        if not search_result:
            print("--- [DEBUG] 검색 결과 영역(.cleanword_type)을 찾을 수 없음 ---")
            return None
            
        # 2. 영어 단어 추출 (class="txt_clebsch")
        word_element = search_result.select_one('.txt_clebsch')
        if not word_element:
            print("--- [DEBUG] 단어 텍스트(.txt_clebsch)를 찾을 수 없음 ---")
            return None
        english = word_element.text.strip()
        
        # 3. 뜻 추출 (class="list_search" 내부의 "txt_search")
        meanings_list = search_result.select('.list_search .txt_search')
        if not meanings_list:
            print("--- [DEBUG] 뜻(.txt_search)을 찾을 수 없음 ---")
            return None
            
        korean = ", ".join([m.text.strip() for m in meanings_list])
        
        print(f"--- [DEBUG] 크롤링 성공: {english} -> {korean} ---")
        
        return {
            'english': english,
            'korean': korean,
            'source': 'external'
        }
        
    except Exception as e:
        print(f"--- [DEBUG] 크롤링 예외 발생: {e} ---")
        return None