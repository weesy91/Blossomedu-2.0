import requests
from django.utils import timezone
from django.db.models.functions import Lower
from .models import TestResultDetail, MonthlyTestResultDetail, Word, TestResult, PersonalWrongWord

# ==============================================================================
# [1] 기존 로직: 오답 단어 추출 (이 부분이 없으면 에러가 납니다!)
# ==============================================================================
def get_vulnerable_words(profile):
    """
    [STRICT MODE] 오답 노트(PersonalWrongWord)에 있는 단어만 반환
    - 검색 추가 단어(MasterWord only)도 포함하여 Word 객체처럼 포장해서 반환
    - 기존 '취약 단어 자동 감지(25% 룰)'는 제거됨
    """
    # 1. 학생이 직접 추가한 오답 단어 수집 (유일한 소스)
    personal_wrongs = PersonalWrongWord.objects.filter(
        student=profile,
        success_count__lt=3
    ).select_related('word', 'word__book', 'master_word') # optimize query

    final_words = []
    seen_ids = set() # (word_id, master_word_id) tuple to dedupe logic if needed? 
                     # PersonalWrongWord is unique by (student, master_word), so just listing them is fine.
    
    # We need to return objects that look like 'Word' model for the frontend/test loop
    # attributes needed: id (can be None), master_word, english, korean, book_id (optional)
    
    class SearchWordWrapper:
        def __init__(self, master_word, korean_hint=""):
            self.id = None # No real Word ID
            self.master_word = master_word
            self.english = master_word.text
            # [Fix] 검색 단어는 뜻이 DB에 없으므로 (MasterWord는 뜻 안가짐), 
            # WordMeaning에서 가져오거나 해야 함. 하지만 여기선 대표 뜻 1개만 필요.
            # 검색 단어 추가 시 뜻을 저장하지 않으므로, 실시간 조회하거나 빈칸.
            # 다행히 start_test 할때 get_primary_pos나 뜻을 다시 조회하긴 함.
            # get_vulnerable_words -> start_test -> response
            
            # MasterWord에 연결된 뜻 중 하나 가져오기 (임시)
            meanings = list(master_word.meanings.all())
            if meanings:
                self.korean = meanings[0].meaning
            else:
                self.korean = "뜻 없음 (검색 단어)"
            
            self.number = 0 # Dummy day
            self.book_id = 0 # Dummy book

    for pw in personal_wrongs:
        if pw.word:
            # 교재에 있는 단어면 그대로 사용
            final_words.append(pw.word)
        elif pw.master_word:
            # 검색 단어면 래퍼 생성
            wrapper = SearchWordWrapper(pw.master_word)
            final_words.append(wrapper)
            
    return final_words

def is_monthly_test_period():
    import calendar
    now = timezone.now()
    last_day = calendar.monthrange(now.year, now.month)[1]
    return now.day > (last_day - 8)

# ==============================================================================
# [2] 외부 사전 검색 (구글 번역 API - 다의어 지원 버전)
# ==============================================================================
def crawl_daum_dic(query):
    """
    [업그레이드] 구글 번역 API (다의어 지원)
    - dt=['t', 'bd'] 파라미터를 통해 기본 번역 + 사전 정보(여러 뜻)를 함께 요청합니다.
    - [FIX] 오타 검색 시 spellchecker로 먼저 교정 후 API 호출
    """
    print(f"--- [DEBUG] 구글 번역 API 요청(다의어): {query} ---")
    
    # [NEW] 스펠체크로 오타 교정 시도
    corrected_query = query
    try:
        from spellchecker import SpellChecker
        spell = SpellChecker()
        # 단어가 사전에 없으면 가장 가까운 단어로 교정
        if query.lower() not in spell:
            correction = spell.correction(query.lower())
            if correction and correction != query.lower():
                corrected_query = correction
                print(f"--- [DEBUG] 스펠체크 교정: {query} -> {corrected_query} ---")
    except ImportError:
        print("--- [DEBUG] spellchecker 라이브러리 없음, 오타 교정 건너뜀 ---")
    except Exception as e:
        print(f"--- [DEBUG] 스펠체크 실패: {e} ---")
    try:
        url = "https://translate.googleapis.com/translate_a/single"
        
        # t: 문장 번역(Translation), bd: 사전 정보(Back Dictionary)
        params = {
            "client": "gtx",
            "sl": "en",
            "tl": "ko",
            "dt": ["t", "bd"], 
            "q": corrected_query  # [FIX] 교정된 쿼리로 API 호출
        }
        
        response = requests.get(url, params=params, timeout=5)
        
        if response.status_code != 200:
            print(f"--- [DEBUG] 응답 오류: {response.status_code} ---")
            return None
        
        data = response.json()
        
        # [FIX] 기본값은 교정된 검색어, 사전 데이터에서 올바른 단어 추출 시도
        english = corrected_query
        korean_candidates = []
        
        # [PRIORITY 1] data[7]에 오타 수정 제안이 있을 수 있음 ("Did you mean...")
        # 이걸 먼저 체크해야 함!
        try:
            if len(data) > 7 and data[7] and len(data[7]) > 0:
                spell_corrected = data[7][0]
                if spell_corrected and isinstance(spell_corrected, str):
                    # HTML 태그 제거
                    spell_corrected = spell_corrected.replace('<b>', '').replace('</b>', '').replace('<i>', '').replace('</i>', '')
                    if spell_corrected.strip().lower() != query.lower():
                        english = spell_corrected.strip()
                        print(f"--- [DEBUG] 오타 수정됨(SpellCheck data[7]): {query} -> {english} ---")
        except Exception as e:
            print(f"--- [DEBUG] data[7] 체크 실패: {e} ---")
        
        # [PRIORITY 2] data[0][0][1]에 오타 수정된 원문이 있을 수 있음
        if english == query:
            try:
                if data and data[0] and data[0][0] and len(data[0][0]) > 1:
                    corrected_source = data[0][0][1]
                    if corrected_source and isinstance(corrected_source, str) and corrected_source.lower() != query.lower():
                        english = corrected_source.strip()
                        print(f"--- [DEBUG] 오타 수정됨(Source data[0][0][1]): {query} -> {english} ---")
            except Exception:
                pass

        if len(data) > 1 and data[1]:
            formatted_meanings = []
            
            # POS Mapping (Google -> App Standard)
            POS_MAP = {
                'noun': '명사',
                'verb': '동사',
                'adjective': '형용사',
                'adverb': '부사',
                'preposition': '전치사',
                'conjunction': '접속사',
                'pronoun': '대명사',
                'interjection': '감탄사',
                'article': '관사',
                'abbreviation': '약어',
                'prefix': '접두사',
                'suffix': '접미사',
            }

            for part_of_speech in data[1]:
                if isinstance(part_of_speech, list) and len(part_of_speech) > 1:
                    raw_pos = part_of_speech[0] # noun, verb, etc.
                    # Map to Korean or use raw if not found
                    pos_label = POS_MAP.get(raw_pos, raw_pos) 
                    
                    meanings = part_of_speech[1]
                    
                    if isinstance(meanings, list):
                        # Limit to top 3 meanings per POS
                        pos_meanings = []
                        for m in meanings[:3]:
                            if m and m not in pos_meanings:
                                pos_meanings.append(m)
                                
                        if pos_meanings:
                            # [명사] 뜻1, 뜻2
                            formatted_meanings.append(f"[{pos_label}] {', '.join(pos_meanings)}")
            
            if formatted_meanings:
                korean = " ".join(formatted_meanings)
            else:
                 # Fallback
                 korean = ", ".join(korean_candidates[:6]) if korean_candidates else ""
            
        # 2. 사전 데이터가 없으면 기본 번역(data[0])을 사용
        else:
            if data and data[0] and data[0][0]:
                korean = data[0][0][0]
            else:
                return None

        print(f"--- [DEBUG] 번역 성공(다의어): {english} -> {korean} ---")
        
        return {
            'english': english,
            'korean': korean,
            'source': 'google_translate'
        }
        
    except Exception as e:
        print(f"--- [DEBUG] 예외 발생: {e} ---")
        return None
