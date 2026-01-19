
import os
import django
import sys

# Setup Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from vocab.models import WordBook, Word
from vocab.services import generate_test_questions

def debug_range_logic():
    print("=== Debugging Range Logic ===")
    
    # 1. Inspect Books
    books = WordBook.objects.all()
    print(f"Total Books: {books.count()}")
    
    if books.count() == 0:
        print("No books found.")
        return

    # Pick the most recent book or the one likely being tested
    book = books.first() 
    print(f"Target Book: {book.title} (ID: {book.id})")
    
    # Check words distribution
    words = Word.objects.filter(book=book)
    print(f"Total Words in Book: {words.count()}")
    
    numbers = words.values_list('number', flat=True).distinct().order_by('number')
    print(f"Word Numbers available: {list(numbers)}")
    
    # 2. Simulate Service Logic
    day_range = "1-60"
    print(f"\nTesting Range: '{day_range}'")
    
    targets = []
    try:
        for chunk in str(day_range).split(','):
            chunk = chunk.replace('Day', '').replace('day', '').replace(' ', '')
            if '-' in chunk:
                s, e = map(int, chunk.split('-'))
                # IMPORTANT: In service logic, range(s, e+1) is used
                targets.extend(range(s, e + 1))
            else:
                targets.append(int(chunk))
        print(f"Parsed Targets (First 10): {targets[:10]} ... Total {len(targets)}")
    except Exception as e:
        print(f"Parsing Failed: {e}")
        
    # 3. Perform Filter
    filtered_words = words.filter(number__in=targets)
    print(f"Filtered Results Count: {filtered_words.count()}")
    
    if filtered_words.count() == 0:
        print("!!! No words matched the filter. Check 'Word.number' field values vs 'targets'.")
    else:
        print(f"First 5 words: {[w.english for w in filtered_words[:5]]}")

if __name__ == "__main__":
    debug_range_logic()
