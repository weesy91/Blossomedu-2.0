import os
import django
import sys

sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.urls import get_resolver

def list_urls(urlpatterns, prefix=''):
    for entry in urlpatterns:
        if hasattr(entry, 'url_patterns'):
            list_urls(entry.url_patterns, prefix + str(entry.pattern))
        else:
            print(prefix + str(entry.pattern))

if __name__ == '__main__':
    from config.urls import urlpatterns
    with open('urls_dump.txt', 'w', encoding='utf-8') as f:
        sys.stdout = f
        print("=== Registered URLs ===")
        list_urls(urlpatterns)
