import requests
import json

url = "https://translate.googleapis.com/translate_a/single"
params = {
    "client": "gtx",
    "sl": "en",
    "tl": "ko",
    "dt": ["t", "bd"],
    "q": "disappointe"
}

response = requests.get(url, params=params, timeout=10)
data = response.json()

print(f"Total items in response: {len(data)}")
print("=" * 50)

for i, item in enumerate(data):
    if item is not None:
        print(f"\ndata[{i}]:")
        print(json.dumps(item, ensure_ascii=False, indent=2)[:500])
        print("...")
