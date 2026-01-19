import argparse
import os
import sys


def setup_django():
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
    try:
        import django
    except ImportError as exc:
        raise SystemExit("Django not available. Run from project venv.") from exc
    django.setup()


def backfill_word_meanings(apply_changes: bool, limit: int | None) -> dict:
    from vocab.models import Word, MasterWord, WordMeaning
    from vocab import services

    counts = {
        "words_seen": 0,
        "master_word_created": 0,
        "word_master_linked": 0,
        "meaning_created": 0,
        "meaning_pos_updated": 0,
    }

    qs = Word.objects.select_related("master_word")
    if limit:
        qs = qs[:limit]

    for word in qs.iterator():
        counts["words_seen"] += 1
        if not word.english:
            continue

        master_word = word.master_word
        if master_word is None:
            master_word, created = MasterWord.objects.get_or_create(text=word.english)
            if created:
                counts["master_word_created"] += 1
            if apply_changes:
                word.master_word = master_word
                word.save(update_fields=["master_word"])
                counts["word_master_linked"] += 1

        if not word.korean:
            continue

        entries = services.parse_meaning_tokens(word.korean)
        for entry in entries:
            meaning = entry["meaning"]
            if not meaning:
                continue
            existing = WordMeaning.objects.filter(
                master_word=master_word,
                meaning=meaning,
            ).first()
            if existing is None:
                counts["meaning_created"] += 1
                if apply_changes:
                    WordMeaning.objects.create(
                        master_word=master_word,
                        meaning=meaning,
                        pos=entry["pos"],
                    )
            else:
                if entry["manual"] and existing.pos != entry["pos"]:
                    counts["meaning_pos_updated"] += 1
                    if apply_changes:
                        existing.pos = entry["pos"]
                        existing.save(update_fields=["pos"])

    return counts


def backfill_personal_wrong(apply_changes: bool, dedupe: bool) -> dict:
    from vocab.models import PersonalWrongWord, MasterWord

    counts = {
        "pww_seen": 0,
        "pww_master_linked": 0,
        "pww_deduped": 0,
    }

    qs = PersonalWrongWord.objects.select_related("word", "master_word", "student")
    for pw in qs.iterator():
        counts["pww_seen"] += 1
        if pw.master_word_id:
            continue
        if not pw.word_id or not pw.word or not pw.word.english:
            continue
        master_word = pw.word.master_word
        if master_word is None:
            master_word, _ = MasterWord.objects.get_or_create(text=pw.word.english)
            if apply_changes:
                pw.word.master_word = master_word
                pw.word.save(update_fields=["master_word"])
        if apply_changes:
            pw.master_word = master_word
            pw.save(update_fields=["master_word"])
        counts["pww_master_linked"] += 1

    if dedupe:
        dupes = {}
        for pw in PersonalWrongWord.objects.exclude(master_word__isnull=True).iterator():
            key = (pw.student_id, pw.master_word_id)
            dupes.setdefault(key, []).append(pw)

        for items in dupes.values():
            if len(items) < 2:
                continue
            items.sort(key=lambda x: (x.success_count, x.last_correct_at or 0), reverse=True)
            keep = items[0]
            for extra in items[1:]:
                counts["pww_deduped"] += 1
                if apply_changes:
                    extra.delete()

    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description="Backfill word meanings and personal wrong data.")
    parser.add_argument("--apply", action="store_true", help="Apply changes (default: dry-run)")
    parser.add_argument("--limit", type=int, default=None, help="Limit number of Word rows to scan")
    parser.add_argument(
        "--fix-personal-wrong",
        action="store_true",
        help="Backfill PersonalWrongWord.master_word from legacy word links",
    )
    parser.add_argument(
        "--dedupe-personal-wrong",
        action="store_true",
        help="Deduplicate PersonalWrongWord by (student, master_word)",
    )
    args = parser.parse_args()

    setup_django()

    print("== Backfill WordMeanings ==")
    word_counts = backfill_word_meanings(args.apply, args.limit)
    for k, v in word_counts.items():
        print(f"{k}: {v}")

    if args.fix_personal_wrong or args.dedupe_personal_wrong:
        print("== Backfill PersonalWrongWord ==")
        pww_counts = backfill_personal_wrong(args.apply, args.dedupe_personal_wrong)
        for k, v in pww_counts.items():
            print(f"{k}: {v}")

    if not args.apply:
        print("Dry-run only. Re-run with --apply to write changes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
