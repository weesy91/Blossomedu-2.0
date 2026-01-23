"""
중복 과제 정리 명령어

사용법:
  python manage.py cleanup_duplicate_assignments          # Dry-run (삭제 없이 확인만)
  python manage.py cleanup_duplicate_assignments --apply  # 실제 삭제 실행
"""

from django.core.management.base import BaseCommand
from django.db.models import Count
from academy.models import AssignmentTask, AssignmentSubmission


class Command(BaseCommand):
    help = '중복 생성된 과제를 정리합니다. 제출된 과제는 유지하고, 미제출 중복만 삭제합니다.'

    def add_arguments(self, parser):
        parser.add_argument(
            '--apply',
            action='store_true',
            help='실제로 삭제를 수행합니다. 없으면 dry-run 모드로 확인만 합니다.',
        )
        parser.add_argument(
            '--student',
            type=int,
            help='특정 학생 ID만 처리',
        )

    def handle(self, *args, **options):
        apply_changes = options['apply']
        student_id = options.get('student')

        if not apply_changes:
            self.stdout.write(self.style.WARNING(
                '⚠️  DRY-RUN 모드입니다. 실제 삭제하려면 --apply 옵션을 추가하세요.\n'
            ))

        # 1. 같은 origin_log와 title을 가진 과제 그룹 찾기
        queryset = AssignmentTask.objects.exclude(origin_log__isnull=True)
        
        if student_id:
            queryset = queryset.filter(student_id=student_id)

        # origin_log + title 기준으로 그룹화하여 2개 이상인 경우 찾기
        duplicates = (
            queryset
            .values('origin_log_id', 'title')
            .annotate(count=Count('id'))
            .filter(count__gt=1)
        )

        total_duplicates = 0
        total_to_delete = 0
        deleted_ids = []

        for dup in duplicates:
            origin_log_id = dup['origin_log_id']
            title = dup['title']
            count = dup['count']

            # 같은 그룹의 과제들 조회
            tasks = AssignmentTask.objects.filter(
                origin_log_id=origin_log_id,
                title=title
            ).order_by('id')

            self.stdout.write(f"\n📋 중복 그룹 발견: origin_log={origin_log_id}, title=\"{title[:50]}\" ({count}개)")

            submitted_task = None
            completed_task = None
            tasks_to_delete = []

            for task in tasks:
                has_submission = AssignmentSubmission.objects.filter(task=task).exists()
                is_completed = task.is_completed

                status_str = "✅ 제출됨" if has_submission else ("🟢 완료" if is_completed else "❌ 미제출")
                self.stdout.write(f"   - ID {task.id}: {status_str} (due: {task.due_date.date()})")

                if has_submission:
                    submitted_task = task
                elif is_completed:
                    completed_task = task
                else:
                    tasks_to_delete.append(task)

            # 삭제 대상 결정
            # 제출된 과제가 있으면: 나머지 미제출 모두 삭제
            # 완료된 과제만 있으면: 미제출 삭제
            # 모두 미제출이면: 가장 오래된 것만 유지
            keep_task = submitted_task or completed_task

            if keep_task:
                # 제출/완료된 과제가 있으니 미제출만 삭제 대상
                pass
            else:
                # 모두 미제출인 경우, 가장 오래된 것만 유지
                if tasks_to_delete:
                    keep_task = tasks_to_delete[0]  # ID가 가장 작은 것
                    tasks_to_delete = tasks_to_delete[1:]

            if tasks_to_delete:
                self.stdout.write(self.style.WARNING(
                    f"   🗑️  삭제 대상: {[t.id for t in tasks_to_delete]}"
                ))
                total_to_delete += len(tasks_to_delete)
                deleted_ids.extend([t.id for t in tasks_to_delete])

                if apply_changes:
                    for task in tasks_to_delete:
                        task.delete()
                        self.stdout.write(self.style.SUCCESS(f"   ✅ ID {task.id} 삭제됨"))

            total_duplicates += count

        # 결과 요약
        self.stdout.write('\n' + '=' * 50)
        self.stdout.write(f'📊 결과 요약:')
        self.stdout.write(f'   중복 그룹 수: {len(duplicates)}')
        self.stdout.write(f'   총 중복 과제 수: {total_duplicates}')
        self.stdout.write(f'   삭제 대상 수: {total_to_delete}')

        if apply_changes:
            self.stdout.write(self.style.SUCCESS(f'\n✅ {total_to_delete}개 과제가 삭제되었습니다!'))
        else:
            self.stdout.write(self.style.WARNING(
                f'\n⚠️  --apply 옵션을 추가하면 {total_to_delete}개 과제가 삭제됩니다.'
            ))
            if deleted_ids:
                self.stdout.write(f'   삭제 예정 ID: {deleted_ids[:20]}...' if len(deleted_ids) > 20 else f'   삭제 예정 ID: {deleted_ids}')
