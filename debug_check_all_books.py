
import os
import django
from django.db.models import Min, Max, Count

# Setup Django environment
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from vocab.models import WordBook, Word


def inspect_all_books():
    with open('debug_output_books.txt', 'w', encoding='utf-8') as f:
        f.write("=== Inspecting All WordBooks ===\n")
        books = WordBook.objects.all()
        
        for book in books:
            words = Word.objects.filter(book=book)
            count = words.count()
            if count == 0:
                f.write(f"[Book ID: {book.id}] '{book.title}': No words.\n")
                continue
                
            stats = words.aggregate(Min('number'), Max('number'))
            min_day = stats['number__min']
            max_day = stats['number__max']
            
            # Check distinct day counts
            distinct_days = words.values('number').distinct().count()
            
            f.write(f"[Book ID: {book.id}] '{book.title}': {count} words. Days: {min_day}~{max_day} (Distinct Days: {distinct_days})\n")
            
            # Sample numbers if strange
            if distinct_days < 5:
                sample_nums = list(words.values_list('number', flat=True).distinct()[:10])
                f.write(f"    -> Sample Days: {sample_nums}\n")

if __name__ == "__main__":
    inspect_all_books()
