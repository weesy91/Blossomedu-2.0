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
    다음 어학사전에서 단어의 뜻을 검색하여 반환합니다. (개선된 버전 V2)
    """
    print(f"--- [DEBUG] 크롤링 시작: {query} ---")
    try:
        url = f"https://dic.daum.net/search.do?q={query}&dic=eng"
        headers = {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
        }
        response = requests.get(url, headers=headers, timeout=5)
        
        if response.status_code != 200:
            print(f"--- [DEBUG] 응답 오류: {response.status_code} ---")
            return None
            
        soup = BeautifulSoup(response.text, 'html.parser')
        
        # [전략 변경] 특정 컨테이너(cleanword_type)에 의존하지 않고, 핵심 클래스를 바로 찾습니다.
        
        # 1. 영어 단어 추출 (class="txt_clebsch")
        # 검색 결과 페이지에서 가장 먼저 나오는 '헤드워드'를 찾습니다.
        word_element = soup.select_one('.txt_clebsch')
        
        # 만약 txt_clebsch가 없으면 tit_clebsch 등 다른 이름 시도 (혹은 검색 결과 없음)
        if not word_element:
            word_element = soup.select_one('.tit_clebsch')
            
        if not word_element:
            print("--- [DEBUG] 단어 텍스트(.txt_clebsch)를 찾을 수 없음 ---")
            return None
            
        english = word_element.text.strip()
        
        # 2. 뜻 추출 (class="list_search" 내부의 "txt_search")
        # 단어 바로 근처에 있는 뜻 목록을 찾아야 정확도가 높습니다.
        # word_element의 부모나 형제 요소 중에서 list_search를 찾는 것이 안전하지만,
        # 일단 가장 먼저 나오는 뜻 목록을 가져옵니다.
        meanings_list = soup.select('.list_search .txt_search')
        
        # 만약 list_search 구조가 아니면, 일반 list_mean 구조 시도
        if not meanings_list:
            meanings_list = soup.select('.list_mean .txt_mean')

        if not meanings_list:
            print("--- [DEBUG] 뜻(.txt_search)을 찾을 수 없음 ---")
            return None
            
        # 상위 3개 뜻만 가져오기
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