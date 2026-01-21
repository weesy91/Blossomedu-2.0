from django.core.management.base import BaseCommand
from django.db.models import Q
from core.models.users import StudentProfile
from messaging.models import Conversation


class Command(BaseCommand):
    help = '기존 학생들의 담당 선생님과 대화방을 일괄 생성합니다.'

    def handle(self, *args, **options):
        students = StudentProfile.objects.filter(user__is_active=True)
        created_count = 0

        for student in students:
            student_user = student.user

            # 구문 선생님
            if student.syntax_teacher:
                if self._create_if_not_exists(student_user, student.syntax_teacher):
                    created_count += 1
                    self.stdout.write(f"  ✓ {student.name} ↔ {student.syntax_teacher.first_name} (구문)")

            # 독해 선생님
            if student.reading_teacher:
                if self._create_if_not_exists(student_user, student.reading_teacher):
                    created_count += 1
                    self.stdout.write(f"  ✓ {student.name} ↔ {student.reading_teacher.first_name} (독해)")

            # 특강 선생님
            if student.extra_class_teacher:
                if self._create_if_not_exists(student_user, student.extra_class_teacher):
                    created_count += 1
                    self.stdout.write(f"  ✓ {student.name} ↔ {student.extra_class_teacher.first_name} (특강)")

        self.stdout.write(self.style.SUCCESS(f'\n총 {created_count}개의 대화방이 생성되었습니다.'))

    def _create_if_not_exists(self, user1, user2):
        """대화방이 없으면 생성, 있으면 스킵"""
        if user1.id == user2.id:
            return False

        exists = Conversation.objects.filter(
            Q(participant1=user1, participant2=user2) |
            Q(participant1=user2, participant2=user1)
        ).exists()

        if exists:
            return False

        Conversation.objects.create(participant1=user1, participant2=user2)
        return True
