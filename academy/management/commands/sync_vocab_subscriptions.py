from django.core.management.base import BaseCommand

from academy.models import AssignmentTask
from vocab.models import PersonalWordBook


class Command(BaseCommand):
    help = "Backfill PersonalWordBook from vocab assignments."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show how many subscriptions would be created.",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]

        pairs = (
            AssignmentTask.objects.filter(related_vocab_book_id__isnull=False)
            .values_list("student_id", "related_vocab_book_id")
            .distinct()
        )

        created_count = 0
        for student_id, book_id in pairs:
            if dry_run:
                if not PersonalWordBook.objects.filter(
                    student_id=student_id, book_id=book_id
                ).exists():
                    created_count += 1
                continue

            _, created = PersonalWordBook.objects.get_or_create(
                student_id=student_id, book_id=book_id
            )
            if created:
                created_count += 1

        if dry_run:
            self.stdout.write(
                self.style.WARNING(
                    "[DRY RUN] {} subscriptions would be created.".format(
                        created_count
                    )
                )
            )
        else:
            self.stdout.write(
                self.style.SUCCESS(
                    "Created {} missing subscriptions.".format(created_count)
                )
            )
