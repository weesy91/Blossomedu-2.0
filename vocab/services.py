# vocab/services.py
from django.utils import timezone
# [수정] StudentProfile import 불필요 (인자로 받을 것이므로)

def calculate_score(details_data):
    """
    서버 사이드 채점 로직
    1. 띄어쓰기 무시 (공백 제거)
    2. 콤마(,)로 구분된 정답 중 하나라도 맞으면 정답 인정
    3. 대소문자 무시 (선택 사항, 여기선 적용함)
    """
    score = 0
    wrong_count = 0
    processed_details = []

    for item in details_data:
        # 학생 답: 공백 제거 & 소문자 변환
        user_input = item.get('user_input', '')
        user_clean = user_input.replace(" ", "").strip().lower()
        
        # 정답지: 원본 가져오기
        ans_origin = item.get('korean', '')
        
        # [핵심 로직] 콤마로 쪼개고, 각각 정제(공백제거+소문자)하여 리스트로 만듦
        # 예: "apple, 사과" -> ["apple", "사과"]
        ans_candidates = [
            a.replace(" ", "").strip().lower() 
            for a in ans_origin.split(',')
        ]
        
        # 학생 답이 후보군 안에 있으면 정답!
        is_correct = (user_clean in ans_candidates)
        
        if is_correct:
            score += 1
        else:
            wrong_count += 1
            
        processed_details.append({
            'q': item.get('english'),
            'u': user_input,      # 원본 입력값 저장
            'a': ans_origin,      # 원본 정답 저장
            'c': is_correct
        })
        
    return score, wrong_count, processed_details

def update_cooldown(profile, mode, score, test_range=None):
    """
    점수에 따라 쿨타임(재시험 대기시간) 설정
    [수정] user 대신 profile 객체를 직접 받습니다.
    """
    PASS_SCORE = 27
    
    # 1. 도전 모드
    if mode == 'challenge':
        if score >= PASS_SCORE: 
            profile.last_failed_at = None
        else: 
            profile.last_failed_at = timezone.now()
            
    # 2. 오답 모드 (또는 오답집중 범위)
    elif mode == 'wrong' or test_range == '오답집중':
        if score >= PASS_SCORE: 
            profile.last_wrong_failed_at = None
        else: 
            profile.last_wrong_failed_at = timezone.now()
            
    profile.save()