
import urllib.request
import urllib.error

url = "http://127.0.0.1:8000/vocab/api/v1/tests/start_test/"

try:
    print(f"Checking URL: {url}")
    with urllib.request.urlopen(url) as response:
        print(f"Status Code: {response.getcode()}")
except urllib.error.HTTPError as e:
    print(f"Status Code: {e.code}")
    print(f"Reason: {e.reason}")
except urllib.error.URLError as e:
    print(f"URL Error: {e.reason}")
except Exception as e:
    print(f"Error: {e}")
