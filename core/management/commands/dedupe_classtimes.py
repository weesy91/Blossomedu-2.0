from collections import defaultdict

from django.core.management.base import BaseCommand
from django.db import transaction

from academy.models import TemporarySchedule
from core.models import ClassTime, StudentProfile


class Command(BaseCommand):
    help = "Deduplicate ClassTime entries by branch/day/start/end/class_type."

    def add_arguments(self, parser):
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Show what would change without updating or deleting.",
        )
        parser.add_argument(
            "--keep",
            choices=["min", "max"],
            default="min",
            help="Choose whether to keep the lowest or highest id per group.",
        )

    def handle(self, *args, **options):
        dry_run = options["dry_run"]
        keep_min = options["keep"] == "min"

        groups = defaultdict(list)
        for class_time in ClassTime.objects.all():
            key = (
                class_time.branch_id,
                class_time.day,
                class_time.start_time,
                class_time.end_time,
                class_time.class_type,
            )
            groups[key].append(class_time)

        duplicate_groups = [group for group in groups.values() if len(group) > 1]
        if not duplicate_groups:
            self.stdout.write(self.style.SUCCESS("No duplicate class times found."))
            return

        total_deleted = 0
        with transaction.atomic():
            for group in duplicate_groups:
                group_sorted = sorted(group, key=lambda item: item.id)
                keeper = group_sorted[0] if keep_min else group_sorted[-1]
                dupes = [item for item in group_sorted if item.id != keeper.id]
                dup_ids = [item.id for item in dupes]
                if not dup_ids:
                    continue

                self.stdout.write(
                    "Keep id={} (branch={}, day={}, {}-{}, {}), merge {}".format(
                        keeper.id,
                        keeper.branch_id,
                        keeper.day,
                        keeper.start_time,
                        keeper.end_time,
                        keeper.class_type,
                        dup_ids,
                    )
                )

                if dry_run:
                    continue

                StudentProfile.objects.filter(syntax_class_id__in=dup_ids).update(
                    syntax_class=keeper
                )
                StudentProfile.objects.filter(reading_class_id__in=dup_ids).update(
                    reading_class=keeper
                )
                StudentProfile.objects.filter(extra_class_id__in=dup_ids).update(
                    extra_class=keeper
                )
                TemporarySchedule.objects.filter(target_class_id__in=dup_ids).update(
                    target_class=keeper
                )

                ClassTime.objects.filter(id__in=dup_ids).delete()
                total_deleted += len(dup_ids)

            if dry_run:
                self.stdout.write(
                    self.style.WARNING(
                        "[DRY RUN] Review the list above before applying."
                    )
                )
            else:
                self.stdout.write(
                    self.style.SUCCESS(
                        "Deleted {} duplicate class times.".format(total_deleted)
                    )
                )
