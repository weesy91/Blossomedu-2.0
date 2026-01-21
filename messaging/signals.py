from django.db.models.signals import post_save
from django.dispatch import receiver
from core.models.users import StudentProfile
from .models import Conversation


@receiver(post_save, sender=StudentProfile)
def auto_create_teacher_conversations(sender, instance, **kwargs):
    """
    학생 저장 시 담당 선생님과의 대화방 자동 생성
    - 구문 선생님 배정 시 → 대화방 생성
    - 독해 선생님 배정 시 → 대화방 생성
    - 선생님 변경 시 → 기존 대화방 보존, 새 대화방 생성
    """
    student_user = instance.user

    # 구문 선생님과의 대화방
    if instance.syntax_teacher:
        _get_or_create_conversation(student_user, instance.syntax_teacher)

    # 독해 선생님과의 대화방
    if instance.reading_teacher:
        _get_or_create_conversation(student_user, instance.reading_teacher)

    # 특강 선생님과의 대화방 (있는 경우)
    if instance.extra_class_teacher:
        _get_or_create_conversation(student_user, instance.extra_class_teacher)


def _get_or_create_conversation(user1, user2):
    """두 사용자 간 대화방이 없으면 생성"""
    from django.db.models import Q

    # user1과 user2가 같으면 무시
    if user1.id == user2.id:
        return None

    # 기존 대화방 확인
    existing = Conversation.objects.filter(
        Q(participant1=user1, participant2=user2) |
        Q(participant1=user2, participant2=user1)
    ).first()

    if existing:
        return existing

    # 새 대화방 생성
    return Conversation.objects.create(
        participant1=user1,
        participant2=user2
    )
