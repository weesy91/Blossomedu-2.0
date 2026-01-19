# vocab/services.py
from django.utils import timezone
import unicodedata
import re
# [수정] StudentProfile import 불필요 (인자로 받을 것이므로)


def clean_text(text):
    """
    텍스트 정제 함수 (업그레이드)
    1. 괄호와 그 안의 내용 제거
    2. [수정] 숫자(1. 2.)와 슬래시(/)를 모두 콤마(,)로 치환하여 정답을 분리함
    3. 나머지 특수문자 제거
    """
    if not text: return ""
    
    # 1. 괄호와 그 안의 내용 제거 (소괄호, 대괄호)
    text = re.sub(r'\(.*?\)|\[.*?\]', '', text)
    
    # 2. [핵심 수정] 숫자목록(1. 2.) 또는 슬래시(/)를 콤마로 변경
    # 예: "신뢰, 믿음 / 신뢰하다" -> "신뢰, 믿음 , 신뢰하다"
    text = re.sub(r'\d+\.|/', ',', text)
    
    # 3. 특수문자 제거 (한글, 영문, 숫자, 콤마, 공백, 물결, 하이픈 제외하고 모두 제거)
    # [Fix] Tilde(~) and Hyphen(-) should be preserved for accurate matching (e.g. "~와 하다", "co-operate")
    text = re.sub(r'[^\w\s,~-]', ' ', text)
    
    return text.strip()

def _normalize_pos_tag(pos):
    if not pos:
        return None
    pos = pos.strip().lower()
    mapping = {
        'a': 'adj',
        'adj': 'adj',
        'ad': 'adv',
        'adv': 'adv',
        'int': 'interj',
        'interj': 'interj',
        'vi': 'v',
        'vt': 'v',
        'v': 'v',
        'n': 'n',
        'pron': 'pron',
        'prep': 'prep',
        'conj': 'conj',
    }
    return mapping.get(pos, pos)

def _infer_pos_from_korean(meaning):
    m = re.sub(r'\(.*?\)|\[.*?\]', '', meaning).strip()
    if not m:
        return 'n'
    if m.endswith('다'):
        return 'v'
    if any(m.endswith(suffix) for suffix in ['ㄴ', '은', '는', '한', '적인', '의']):
        return 'adj'
    if any(m.endswith(suffix) for suffix in ['게', '히', '으로']):
        return 'adv'
    return 'n'

def parse_meaning_tokens(meaning_text):
    if not meaning_text:
        return []

    entries = []
    parts = [p.strip() for p in re.split(r'[,/]', meaning_text)]

    # Manual POS prefixes at the start of a meaning token.
    prefix_re = re.compile(
        r'^(n|v|adj|a|adv|ad|prep|conj|pron|int|vi|vt)(?:\.\s*|\s+)',
        re.IGNORECASE,
    )
    for p in parts:
        if not p:
            continue

        manual_pos = None
        clean = p
        match = prefix_re.match(p)
        if match:
            manual_pos = _normalize_pos_tag(match.group(1))
            clean = p[match.end():].strip()

        if not clean:
            continue

        pos = manual_pos or _infer_pos_from_korean(clean)
        pos = _normalize_pos_tag(pos) or 'n'
        entries.append({'meaning': clean, 'pos': pos, 'manual': manual_pos is not None})

    return entries

def split_meanings_by_pos(meaning_text):
    """
    Returns (grouped, ordered) where grouped is {pos: [meanings...]}.
    Pos tags are normalized to: n, v, adj, adv, pron, prep, conj, interj.
    """
    grouped = {}
    ordered = []
    entries = parse_meaning_tokens(meaning_text)

    for entry in entries:
        pos = entry['pos']
        if pos not in grouped:
            grouped[pos] = []
            ordered.append(pos)
        grouped[pos].append(entry['meaning'])

    return grouped, ordered

def select_meaning_by_pos(meaning_text, pos):
    pos_key = _normalize_pos_tag(pos)
    if not pos_key:
        return None
    grouped, _ = split_meanings_by_pos(meaning_text)
    if pos_key in grouped:
        return ', '.join(grouped[pos_key])
    return None

def get_primary_pos(meaning_text):
    entries = parse_meaning_tokens(meaning_text)
    return entries[0]['pos'] if entries else None

def sync_master_meanings(master_word, meaning_text):
    from .models import WordMeaning

    entries = parse_meaning_tokens(meaning_text)
    for entry in entries:
        meaning = entry['meaning']
        pos = entry['pos']
        wm, created = WordMeaning.objects.get_or_create(
            master_word=master_word,
            meaning=meaning,
            defaults={'pos': pos},
        )
        if entry['manual'] and wm.pos != pos:
            wm.pos = pos
            wm.save(update_fields=['pos'])


def calculate_score(details_data):
    """
    서버 사이드 채점 로직
    - 정답지는 콤마(,)로 구분
    - 비교 시에는 모든 공백을 제거하여 '상호 작용하다' == '상호작용하다' 인정
    """
    score = 0
    wrong_count = 0
    processed_details = []

    for item in details_data:
        user_input = item.get('user_input', '')
        ans_origin = item.get('korean', '')
        
        if not user_input: user_input = ""
        if not ans_origin: ans_origin = ""

        # 1. NFC 정규화 (맥/윈도우 호환성)
        user_norm = unicodedata.normalize('NFC', user_input)
        ans_norm = unicodedata.normalize('NFC', ans_origin)

        # 2. 정답지 전처리 (숫자를 콤마로 변환)
        # "1. 회피하다 2. 외면하다" -> ", 회피하다 , 외면하다"
        cleaned_ans = clean_text(ans_norm)
        
        # 3. 정답 후보군 생성 (콤마로 분리)
        # -> ['', '회피하다', '', '외면하다'] -> ['회피하다', '외면하다']
        ans_candidates = [
            token.strip().lower() 
            for token in cleaned_ans.split(',') 
            if token.strip()
        ]

        # 4. 학생 답안 전처리 (콤마로 분리)
        user_tokens = [
            u.strip().lower() 
            for u in user_norm.split(',') 
            if u.strip()
        ]
        
        # 5. 채점 (공백 무시 비교)
        is_correct = False
        
        # [DEBUG] Print values for investigation
        print(f"[GRADING DEBUG] Question: {item.get('english')}")
        print(f"[GRADING DEBUG] User input: '{user_input}' -> tokens: {user_tokens}")
        print(f"[GRADING DEBUG] Answer: '{ans_origin}' -> candidates: {ans_candidates}")
        
        if not user_tokens:
            is_correct = False
        else:
            for u_token in user_tokens:
                # 학생 답: "상호작용하다" -> "상호작용하다"
                u_compact = u_token.replace(" ", "")
                # [Fix] Remove redundant clean_text to ensure symmetry, or apply consistent logic.
                # u_token is already from user_norm which passed check? No, user_norm is just NFC.
                # user_input is NOT passed through clean_text in step 4?
                # Wait, step 4 splits user_norm.split(','). It DOES NOT call clean_text on user_input!
                # We should apply clean_text to user_input too for consistency.
                
                # Apply clean_text to the token strictly for comparison
                u_clean = clean_text(u_token).replace(" ", "")

                for a_token in ans_candidates:
                    # 정답지: "상호 작용하다" -> "상호작용하다"
                    a_clean = a_token.replace(" ", "")
                    # a_token comes from clean_text(ans_norm), so it is already clean.
                    
                    # [Relaxed Match] Ignore Tilde(~) for comparison if strict match fails
                # [Relaxed Match] Ignore Tilde(~) for comparison if strict match fails
                    if u_clean == a_clean:
                        is_correct = True
                        break
                    
                    # Fallback 1: Ignore tildes
                    if u_clean.replace("~", "") == a_clean.replace("~", ""):
                        is_correct = True
                        break

                    # Fallback 2: Ignore leading particles (에, 와, 을, 를...)
                    # [Advanced Grading] "~에 의존하다" vs "의존하다" -> Match
                    def strip_particles(t):
                        # 1. Remove leading tildes/hyphens
                        t = re.sub(r'^[~-]+\s*', '', t)
                        # 2. Remove leading Korean particles (limiting to common ones)
                        # Caution: simple '에' removal might affect words starting with 에 (에너지).
                        # So we only remove if it looks like a particle pattern from the Answer Key side mostly.
                        # But here strictly stripping common prepositional particles if followed by space or just checking end?
                        # Actually, safe approach: Strip specifically "에", "와", "과", "을", "를" if they are at the start.
                        t = re.sub(r'^(에|와|과|을|를|이|가|로|으로)\s*', '', t) 
                        return t

                    u_stem = strip_particles(u_clean)
                    a_stem = strip_particles(a_clean)
                    
                    if u_stem == a_stem:
                        is_correct = True
                        break
                        
                if is_correct: break
        
        if is_correct:
            score += 1
        else:
            wrong_count += 1
            
        processed_details.append({
            'q': item.get('english'),
            'u': user_input,
            'a': ans_origin,
            'c': is_correct
        })
        
    return score, wrong_count, processed_details

def update_cooldown(profile, mode, score, test_range=None, total_count=None):
    """
    점수에 따라 쿨타임(재시험 대기시간) 설정
    [수정] user 대신 profile 객체를 직접 받습니다.
    """
    pass_by_rate = None
    if total_count and total_count > 0:
        pass_by_rate = (score / total_count) >= 0.9
    else:
        pass_by_rate = score >= 27
    
    # 1. 도전 모드
    if mode == 'challenge':
        if pass_by_rate: 
            profile.last_failed_at = None
        else: 
            profile.last_failed_at = timezone.now()
            
    # 2. 오답 모드 (또는 오답집중 범위)
    elif mode == 'wrong' or test_range == '오답집중' or test_range == 'WRONG_ONLY':
        if pass_by_rate: 
            profile.last_wrong_failed_at = None
        else: 
            profile.last_wrong_failed_at = timezone.now()
            
    profile.save()

def process_snowball_results(student_profile, processed_details):
    """
    [핵심] 채점 후 3-Strike Rule 적용 및 오답 노트 업데이트
    - 틀림 -> PersonalWrongWord 생성/리셋 (success_count=0)
    - 맞음 -> PersonalWrongWord 있으면 success_count +1
    """
    from .models import MasterWord, PersonalWrongWord

    for item in processed_details:
        english = item['q']
        is_correct = item['c']
        
        # 1. MasterWord 식별 (없으면 생성 - 데이터 무결성 보장)
        master_word, _ = MasterWord.objects.get_or_create(text=english)
        
        # 2. 오답 노트 업데이트
        if not is_correct:
            pww, _ = PersonalWrongWord.objects.get_or_create(
                student=student_profile,
                master_word=master_word
            )
            # [Fail]: 틀리면 무조건 스택 초기화 (지옥 시작)
            pww.success_count = 0
            pww.last_correct_at = None # 쿨타임 로직엔 안 쓰이지만, 이력 관리용
            pww.save()
        else:
            # [Success]: 이미 오답 노트에 있는 단어만 스택 증가
            pww = PersonalWrongWord.objects.filter(
                student=student_profile,
                master_word=master_word
            ).first()
            if pww and pww.success_count < 3:
                pww.success_count += 1
                pww.last_correct_at = timezone.now()
                pww.save()
                
    return True

def generate_test_questions(student_profile, book_id, day_range, total_count=30, wrong_word_limit=10):
    """
    [SIMPLIFIED] 단어 시험 출제 로직
    - Snowball 로직 제거됨 (오답 과제는 별도로 부여)
    - 지정된 책(book_id)의 범위(day_range)에서만 출제
    """
    from .models import WordBook, Word
    import random

    questions = []
    
    # book_id가 없거나 0이면 빈 리스트 반환
    if not book_id or str(book_id) == '0':
        return questions
    
    try:
        book = WordBook.objects.get(id=book_id)
        word_qs = Word.objects.filter(book=book)
    except WordBook.DoesNotExist:
        return questions

    # 범위 필터링 (예: "1-5", "1,3,5")
    if day_range != 'ALL':
        try:
            targets = []
            for chunk in str(day_range).split(','):
                chunk = chunk.replace('Day', '').replace('day', '').replace(' ', '')
                if '-' in chunk:
                    s, e = map(int, chunk.split('-'))
                    targets.extend(range(s, e + 1))
                else:
                    targets.append(int(chunk))
            word_qs = word_qs.filter(number__in=targets)
        except: 
            pass
        
    # 랜덤 추출
    candidates = list(word_qs)
    random.shuffle(candidates)
    selected = candidates[:total_count]
    
    for w in selected:
        pos_tag = get_primary_pos(w.korean) if w.korean else None
        questions.append({
            'id': w.master_word.id if w.master_word else None,
            'word_id': w.id,
            'type': f'Day {w.number}',
            'english': w.english,
            'korean': w.korean,
            'pos': pos_tag,
            'is_snowball': False
        })
    
    return questions
