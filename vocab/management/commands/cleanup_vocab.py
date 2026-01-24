from django.core.management.base import BaseCommand
from vocab.models import Word
from vocab.services import clean_text, sync_master_meanings
from django.db import transaction
import logging
import traceback

class Command(BaseCommand):
    help = 'Cleans up Word.korean fields using the new parsing rules'

    def handle(self, *args, **options):
        # Configure File Logging
        logger = logging.getLogger('vocab_cleanup')
        logger.setLevel(logging.INFO)
        # Clear existing handlers
        if logger.hasHandlers():
            logger.handlers.clear()
            
        handler = logging.FileHandler('vocab_cleanup.log', encoding='utf-8')
        handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s'))
        logger.addHandler(handler)
        
        logger.info("Starting vocab cleanup...")
        print("Logging to vocab_cleanup.log...") # Minimal stdout
        
        try:
            words = Word.objects.all()
            total_words = words.count()
            logger.info(f"Total words to process: {total_words}")
            
            updated_count = 0
            
            # Using iterator to avoid memory issues if large
            # Atomic transaction per chunk or whole? Whole might be too big if huge DB.
            # But for safety, let's just do atomic.
            
            with transaction.atomic():
                for word in words.iterator():
                    original = word.korean
                    cleaned = clean_text(original)
                    
                    if original != cleaned:
                        word.korean = cleaned
                        word.save(update_fields=['korean'])
                        
                        if word.master_word:
                            try:
                                sync_master_meanings(word.master_word, cleaned)
                            except Exception as e:
                                logger.warning(f"Failed to sync meaning for {word}: {e}")
                                
                        updated_count += 1
                        if updated_count % 100 == 0:
                            logger.info(f"Updated {updated_count} words...")

            logger.info(f"Successfully updated {updated_count} words out of {total_words}.")
            
        except Exception as e:
            logger.error(f"Fatal Error: {e}")
            logger.error(traceback.format_exc())
            # Re-raise to signal failure to management command
            raise e
