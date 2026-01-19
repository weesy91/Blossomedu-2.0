from datetime import datetime, timedelta
import re

from django.db.models.signals import post_save, pre_save
from django.dispatch import receiver
from django.utils import timezone

from .models import AssignmentTask, ClassLog
from vocab.models import PersonalWordBook


def _as_date(value):
    if isinstance(value, datetime):
        return value.date()
    return value


@receiver(pre_save, sender=ClassLog)
def capture_prev_state(sender, instance, **kwargs):
    if not instance.pk:
        return
    prev = ClassLog.objects.filter(pk=instance.pk).values(
        "date",
        "hw_due_date",
        "hw_vocab_range",
        "hw_vocab_book_id",
        "hw_main_book_id",
    ).first()
    instance._prev_state = prev


@receiver(post_save, sender=ClassLog)
def create_assignment_from_log(sender, instance, created, **kwargs):
    """
    수업 일지(ClassLog)가 저장될 때, 자동으로 다음 주 과제(AssignmentTask)를 생성/갱신합니다.
    """

    def _get_due_date(log):
        return log.hw_due_date or (log.date + timedelta(days=7))

    def _get_start_date(log, use_today=False):
        base_start = log.date + timedelta(days=1)
        if not use_today:
            return base_start
        today = timezone.localdate()
        return max(base_start, today)

    def _parse_range(range_str):
        if not range_str:
            return []
        days = set()
        for chunk in range_str.split(","):
            chunk = chunk.strip()
            if not chunk:
                continue
            if "-" in chunk:
                try:
                    s, e = map(int, chunk.split("-"))
                except ValueError:
                    continue
                if s > e:
                    s, e = e, s
                days.update(range(s, e + 1))
            else:
                try:
                    days.add(int(chunk))
                except ValueError:
                    continue
        return sorted(days)

    def _is_submitted(task):
        try:
            _ = task.submission
            return True
        except Exception:
            return False

    def _chunk_days(days, total_days):
        if not days:
            return []
        if total_days < 1:
            total_days = 1
        per_day = (len(days) + total_days - 1) // total_days
        chunks = []
        idx = 0
        while idx < len(days):
            chunks.append(days[idx : idx + per_day])
            idx += per_day
        return chunks

    def _create_vocab_tasks(log, days, start_date, due_date):
        due_date_date = _as_date(due_date)
        start_date_date = _as_date(start_date)

        total_days = (due_date_date - start_date_date).days + 1
        if total_days < 1:
            total_days = 1
            start_date_date = due_date_date

        day_chunks = _chunk_days(days, total_days)
        current_date = start_date_date
        tasks_created = 0

        for chunk in day_chunks:
            if not chunk:
                current_date += timedelta(days=1)
                continue
            start_ch = min(chunk)
            end_ch = max(chunk)

            AssignmentTask.objects.create(
                student=log.student,
                teacher=log.teacher,
                origin_log=log,
                assignment_type=AssignmentTask.AssignmentType.VOCAB_TEST,
                title=f"[{log.hw_vocab_book.title}] Day {start_ch}~{end_ch} 암기",
                description=f"{current_date.month}월 {current_date.day}일의 목표입니다. 미루지 마세요!",
                due_date=current_date,
                related_vocab_book=log.hw_vocab_book,
                vocab_range_start=start_ch,
                vocab_range_end=end_ch,
            )
            current_date += timedelta(days=1)
            tasks_created += 1

        print(f"--- [Signal] {log.student.name}: 단어 과제 {tasks_created}개로 분할 생성(N-Split) ---")

    def _create_manual_task(log, due_date):
        range_str = log.hw_main_range or "진도 확인"
        AssignmentTask.objects.create(
            student=log.student,
            teacher=log.teacher,
            origin_log=log,
            assignment_type=AssignmentTask.AssignmentType.MANUAL,
            title=f"[{log.hw_main_book.title}] {range_str} 풀기",
            description="문제를 풀고 인증샷을 제출하세요.",
            due_date=due_date,
        )
        print(f"--- [Signal] {log.student.name} 학생의 교재 과제 자동 생성 완료 ---")

    # 다음 수업일(마감일) 추론: 일단 일주일 뒤로 설정 (실제로는 학생 시간표 조회 필요)
    due_date = _get_due_date(instance)
    start_date = _get_start_date(instance, use_today=False)

    # -------------------------------------------------------
    # A. 단어 과제 생성/갱신 (Type B: VOCAB_TEST) [N-Split 적용]
    # -------------------------------------------------------
    if instance.hw_vocab_book:
        vocab_tasks = AssignmentTask.objects.filter(
            origin_log=instance,
            assignment_type=AssignmentTask.AssignmentType.VOCAB_TEST,
        )

        if created or not vocab_tasks.exists():
            range_str = instance.hw_vocab_range or ""
            days = _parse_range(range_str)
            if days:
                _create_vocab_tasks(instance, days, start_date, due_date)
            else:
                AssignmentTask.objects.create(
                    student=instance.student,
                    teacher=instance.teacher,
                    origin_log=instance,
                    assignment_type=AssignmentTask.AssignmentType.VOCAB_TEST,
                    title=f"[{instance.hw_vocab_book.title}] {range_str} 암기",
                    description="앱 내 단어 시험을 통과하세요.",
                    due_date=due_date,
                    related_vocab_book=instance.hw_vocab_book,
                )
                print(f"--- [Signal] {instance.student.name}: 단어 과제 일반 생성 ---")
        elif not created:
            prev = getattr(instance, "_prev_state", None)
            if prev:
                changed = (
                    prev.get("date") != instance.date
                    or prev.get("hw_due_date") != instance.hw_due_date
                    or prev.get("hw_vocab_range") != instance.hw_vocab_range
                    or prev.get("hw_vocab_book_id") != getattr(instance.hw_vocab_book, "id", None)
                )
            else:
                changed = True

            if changed:
                days = _parse_range(instance.hw_vocab_range or "")
                if not days:
                    for task in vocab_tasks.filter(is_completed=False):
                        if task.due_date != due_date:
                            task.due_date = due_date
                            task.save(update_fields=["due_date"])
                else:
                    completed_days = set()
                    for task in vocab_tasks.filter(is_completed=True):
                        if task.vocab_range_start and task.vocab_range_end:
                            completed_days.update(
                                range(task.vocab_range_start, task.vocab_range_end + 1)
                            )
                    remaining_days = [d for d in days if d not in completed_days]
                    if not remaining_days:
                        for task in vocab_tasks.filter(is_completed=False):
                            if task.due_date != due_date:
                                task.due_date = due_date
                                task.save(update_fields=["due_date"])
                    else:
                        vocab_tasks.filter(is_completed=False).delete()
                        resplit_start = _get_start_date(instance, use_today=True)
                        _create_vocab_tasks(instance, remaining_days, resplit_start, due_date)

    # -------------------------------------------------------
    # B. 교재/일반 과제 생성/갱신 (Type A: MANUAL)
    # -------------------------------------------------------
    if instance.hw_main_book:
        manual_tasks = AssignmentTask.objects.filter(
            origin_log=instance,
            assignment_type=AssignmentTask.AssignmentType.MANUAL,
        )

        if created or not manual_tasks.exists():
            _create_manual_task(instance, due_date)
        elif not created:
            prev = getattr(instance, "_prev_state", None)
            if prev:
                changed = (
                    prev.get("date") != instance.date
                    or prev.get("hw_due_date") != instance.hw_due_date
                    or prev.get("hw_main_book_id") != getattr(instance.hw_main_book, "id", None)
                )
            else:
                changed = True

            if changed:
                for task in manual_tasks:
                    if task.is_completed or _is_submitted(task):
                        continue
                    if task.due_date != due_date:
                        task.due_date = due_date
                        task.save(update_fields=["due_date"])


@receiver(post_save, sender=AssignmentTask)
def ensure_vocab_subscription(sender, instance, **kwargs):
    if not instance.related_vocab_book_id:
        return
    if not instance.student_id:
        return
    PersonalWordBook.objects.get_or_create(
        student_id=instance.student_id,
        book_id=instance.related_vocab_book_id,
    )
