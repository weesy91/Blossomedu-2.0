import os
import django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from django.core.files import File
from django.contrib.auth import get_user_model
from vocab.models import WordBook, MasterWord, WordMeaning, Word, Publisher

User = get_user_model()

# 1. Setup User & Publisher
admin_user, _ = User.objects.get_or_create(username='admin', defaults={'email': 'admin@test.com'})
publisher, _ = Publisher.objects.get_or_create(name='Test Publisher')

# 2. Create WordBook and Upload CSV
csv_path = 'sample_vocab.csv'

# Clean up previous test data
WordBook.objects.filter(title='Test CSV Book').delete()
MasterWord.objects.all().delete() # Clean Master DB for clear test

print("--- [Start] CSV Upload Simulation ---")

try:
    with open(csv_path, 'rb') as f:
        book = WordBook(
            title='Test CSV Book',
            publisher=publisher,
            uploaded_by=admin_user
        )
        book.csv_file.save('sample_vocab.csv', File(f)) # This triggers save() logic
        book.save()


except Exception as e:
    import traceback
    traceback.print_exc()
    print(f"Error: {e}")

print("\n--- [Result] Master Database Verification ---")
for mw in MasterWord.objects.all():
    print(f"\n[MasterWord] {mw.text} (ID: {mw.id})")
    for meaning in mw.meanings.all():
        print(f"  - Meaning: {meaning.meaning} | POS: {meaning.pos}")

print("\n--- [Result] Book Entry Verification ---")
for word in Word.objects.filter(book=book):
    print(f"[Book Entry] Day {word.number}: {word.english} -> {word.korean}")
