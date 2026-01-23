import requests

def test_google_translate(word):
    params = {
        'client': 'gtx',
        'sl': 'en',
        'tl': 'ko',
        'dt': ['t', 'bd'],
        'q': word
    }
    r = requests.get('https://translate.googleapis.com/translate_a/single', params=params, timeout=5)
    data = r.json()
    
    print(f"=== 검색어: {word} ===\n")
    
    # 기본 번역
    print("1. 기본 번역 (data[0]):")
    if data[0] and data[0][0]:
        print(f"   {data[0][0][0]}")
    
    # 사전 데이터 (여러 뜻)
    print("\n2. 사전 데이터 (data[1]) - 다의어:")
    if len(data) > 1 and data[1]:
        korean_candidates = []
        for part_of_speech in data[1]:
            if isinstance(part_of_speech, list) and len(part_of_speech) > 1:
                pos = part_of_speech[0]  # 품사
                meanings = part_of_speech[1]
                print(f"   [{pos}] {meanings[:5]}")
                for m in meanings[:3]:
                    if m and m not in korean_candidates:
                        korean_candidates.append(m)
        
        print(f"\n3. 최종 결과 (콤마 연결):")
        print(f"   {', '.join(korean_candidates[:6])}")
    else:
        print("   사전 데이터 없음")

if __name__ == "__main__":
    test_google_translate("environmental")
    print("\n" + "="*50 + "\n")
    test_google_translate("disappoint")
