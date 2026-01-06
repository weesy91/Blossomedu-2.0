# utils/aligo.py

import requests
import json
from django.conf import settings

# [설정] 알리고 API 정보 (나중에 settings.py로 옮기세요)
ALIGO_API_KEY = "여기에_알리고_API키_입력"
ALIGO_USER_ID = "여기에_알리고_아이디_입력"
SENDER_KEY = "여기에_카카오_발신프로필키_입력" 
SENDER_PHONE = "010-0000-0000" # 알리고에 등록된 발신번호

def send_alimtalk(receiver_phone, template_code, context_data, fallback_msg=""):
    """
    알림톡 전송 함수
    - 템플릿 코드가 유효하지 않으면 전송 실패할 수 있음.
    - 실패 시 문자로 대체 발송(failover) 설정됨.
    """
    if not receiver_phone:
        return False
        
    url = "https://kakaoapi.aligo.in/akv10/alimtalk/send/"
    
    # context_data['content']에 완성된 메시지 본문을 넣어서 호출한다고 가정
    content = context_data.get('content', '')
    
    payload = {
        'apikey': ALIGO_API_KEY,
        'userid': ALIGO_USER_ID,
        'senderkey': SENDER_KEY,
        'tpl_code': template_code,
        'sender': SENDER_PHONE,
        'receiver_1': receiver_phone,
        'subject_1': '블라썸에듀 알림',
        'message_1': content,
        'failover': 'Y', # 카톡 실패 시 문자로 전환
        'fsubject_1': '블라썸에듀 알림',
        'fmessage_1': fallback_msg or content
    }
    
    # 버튼 정보가 있다면 추가 (JSON 문자열 변환 필요)
    if 'button' in context_data:
        payload['button_1'] = json.dumps(context_data['button'])

    try:
        # 실제 전송 (테스트 중에는 주석 처리하고 print만 해도 됨)
        response = requests.post(url, data=payload)
        res_json = response.json()
        
        if res_json['code'] == 0:
            print(f"✅ 알림톡 전송 성공: {receiver_phone}")
            return True
        else:
            print(f"❌ 알림톡 전송 실패({res_json['message']}): {receiver_phone}")
            return False
    except Exception as e:
        print(f"❌ 알림톡 통신 에러: {e}")
        return False