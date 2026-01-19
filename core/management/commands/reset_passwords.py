from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from core.models import StudentProfile

class Command(BaseCommand):
    help = '모든 학생 계정의 비밀번호를 일괄 초기화합니다.'

    def add_arguments(self, parser):
        parser.add_argument('--password', type=str, default='1234', help='설정할 비밀번호 (기본값: 1234)')
        parser.add_argument('--target', type=str, default='all', choices=['all', 'student', 'staff'], help='대상 (all: 전체, student: 학생만, staff: 선생님만)')

    def handle(self, *args, **options):
        new_password = options['password']
        target = options['target']

        users = User.objects.all()

        if target == 'student':
            # 학생 프로필이 있는 유저만 필터링 (또는 user_type 체크 방식에 따라 조정)
            # 여기서는 Staff가 아닌 유저를 대상으로 합니다.
            users = users.filter(is_staff=False, is_superuser=False)
        elif target == 'staff':
            users = users.filter(is_staff=True)
        
        # 슈퍼유저는 제외
        users = users.exclude(is_superuser=True)

        count = 0
        total = users.count()

        self.stdout.write(f"🔄 총 {total}명의 {target} 계정 비밀번호를 '{new_password}'(으)로 변경합니다...")

        for user in users:
            user.set_password(new_password)
            user.save()
            count += 1
            if count % 10 == 0:
                self.stdout.write(f"  - {count}/{total} 완료...")

        self.stdout.write(self.style.SUCCESS(f"✅ 완료! 총 {count}명의 비밀번호가 초기화되었습니다."))
