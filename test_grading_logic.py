
import re
import unicodedata

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
    text = re.sub(r'[^\w\s,~-]', ' ', text)
    
    return text.strip()

def calculate_score_debug(user_input, ans_origin):
    score = 0
    
    if not user_input: user_input = ""
    if not ans_origin: ans_origin = ""

    # 1. NFC 정규화
    user_norm = unicodedata.normalize('NFC', user_input)
    ans_norm = unicodedata.normalize('NFC', ans_origin)

    # 2. 정답지 전처리
    cleaned_ans = clean_text(ans_norm)
    
    # 3. 정답 후보군 생성
    ans_candidates = [
        token.strip().lower() 
        for token in cleaned_ans.split(',') 
        if token.strip()
    ]

    # 4. 학생 답안 전처리
    user_tokens = [
        u.strip().lower() 
        for u in user_norm.split(',') 
        if u.strip()
    ]
    
    # 5. 채점
    is_correct = False
    debug_log = []
    
    if not user_tokens:
        is_correct = False
    else:
        for u_token in user_tokens:
            u_clean = clean_text(u_token).replace(" ", "")

            for a_token in ans_candidates:
                a_clean = a_token.replace(" ", "")
                
                # DEBUG: Compare
                debug_log.append(f"Comparing User '{u_clean}' vs Ans '{a_clean}'")
                
                if u_clean == a_clean:
                    is_correct = True
                    break
                
                # [Relaxed Match] Ignore Tilde(~)
                if u_clean.replace("~", "") == a_clean.replace("~", ""):
                    is_correct = True
                    break

                # Fallback 2: Ignore leading particles
                def strip_particles(t):
                    t = re.sub(r'^[~-]+\s*', '', t)
                    t = re.sub(r'^(에|와|과|을|를|이|가|로|으로)\s*', '', t) 
                    return t

                u_stem = strip_particles(u_clean)
                a_stem = strip_particles(a_clean)
                
                if u_stem == a_stem:
                    is_correct = True
                    break
                    
            if is_correct: break
            
    return is_correct, debug_log, ans_candidates

# Test Cases
test_cases = [
    {
        "word": "meet ~ by chance",
        "user": "우연히 만나다",
        "correct": "~와 우연히 만나다"
    },
    {
        "word": "slight",
        "user": "약간의",
        "correct": "약간의, 하찮은"
    },
    {
        "word": "refuse",
        "user": "거절하다",
        "correct": "거절하다, 거부하다"
    },
    {
        "word": "share",
        "user": "공유하다",
        "correct": "나누다, 공유하다, 몫"
    },
    {
        "word": "provide",
        "user": "제공하다",
        "correct": "공급하다, 제공하다, 대비하다"
    },
    {
        "word": "rely on",
        "user": "의존하다",
        "correct": "~에 의존하다, ~을 신뢰하다"
    },
    {
        "word": "depend on",
        "user": "~에 의존하다",
        "correct": "~에 의존[의지]하다"
    },
    {
        "word": "production",
        "user": "생산",
        "correct": "생산(량)"
    }
]

print("=== Starting Grading Logic Test ===")
for case in test_cases:
    is_correct, logs, candidates = calculate_score_debug(case['user'], case['correct'])
    status = "PASS" if is_correct else "FAIL"
    print(f"\n[{status}] Word: {case['word']}")
    print(f"  User: '{case['user']}'")
    print(f"  Correct: '{case['correct']}'")
    print(f"  Candidates: {candidates}")
    if not is_correct:
        print("  Debug Logs:")
        for log in logs:
            print(f"    {log}")
