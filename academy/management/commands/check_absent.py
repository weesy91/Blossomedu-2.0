from django.core.management.base import BaseCommand
from django.utils import timezone
from datetime import datetime, timedelta
from core.models import StudentProfile
from academy.models import Attendance
from academy.utils import get_today_class_start_time
from utils.aligo import send_alimtalk 

class Command(BaseCommand):
    help = '수업 시작 시간이 지났는데 등원하지 않은 학생을 찾아 자동으로 결석 처리하고 알림을 보냅니다.'

    def handle(self, *args, **options):
        # 로그 파일에 찍힐 시간
        now = timezone.now()
        today = now.date()
        
        # 1. 상태가 'ACTIVE(재원)'인 학생들만 조회 (필요시 filter 조건 추가)
        students = StudentProfile.objects.all() 

        check_count = 0
        absent_created = 0

        for student in students:
            # 2. 이미 오늘 출석(등원/지각/결석) 기록이 있으면 패스
            if Attendance.objects.filter(student=student, date=today).exists():
                continue

            # 3. 오늘 수업 시작 시간 가져오기 (없으면 패스)
            start_time = get_today_class_start_time(student)
            if start_time is None:
                continue

            # 비교를 위해 datetime 객체로 변환
            class_start_dt = timezone.make_aware(datetime.combine(today, start_time))

            # 4. 현재 시간이 수업 시간보다 지났는지 확인
            if now > class_start_dt:
                diff = now - class_start_dt
                minutes_passed = diff.total_seconds() / 60
                
                # (A) 40분 이상 지났으면 -> '결석(ABSENT)' 확정 처리 및 알림 발송
                if minutes_passed >= 40:
                    # [1] 결석 데이터 생성
                    Attendance.objects.create(
                        student=student,
                        date=today,
                        status='ABSENT',
                        memo='시스템 자동 결석 처리 (40분 경과)'
                    )
                    self.stdout.write(self.style.ERROR(f"❌ [결석 처리] {student.name} (수업: {start_time}, {int(minutes_passed)}분 지남)"))
                    absent_created += 1

                    # [2] 알림 문자/카톡 발송 로직 추가
                    # (조건: 알림 발송 설정이 켜져 있는 경우에만)
                    if student.send_attendance_alarm:
                        # 수신자 목록 결정 (어머님/아버님/둘다)
                        targets = []
                        if student.notification_recipient in ['MOM', 'BOTH'] and student.parent_phone_mom:
                            targets.append(student.parent_phone_mom)
                        if student.notification_recipient in ['DAD', 'BOTH'] and student.parent_phone_dad:
                            targets.append(student.parent_phone_dad)
                        
                        # 메시지 내용 구성
                        msg_content = f"[블라썸에듀] 결석 안내\n{student.name} 학생이 정규 수업 시작 후 40분이 경과하여 결석 처리되었습니다.\n\n- 수업 시간: {start_time.strftime('%H:%M')}"

                        # 실제 발송
                        for phone in targets:
                            send_alimtalk(
                                receiver_phone=phone,
                                template_code="WAITING_CODE_2", # [중요] 나중에 승인된 템플릿 코드로 변경하세요
                                context_data={'content': msg_content}
                            )
                
                # (B) 10분 ~ 40분 사이 (현재는 기능 없음)
                elif minutes_passed >= 10:
                    pass

        if absent_created > 0:
            self.stdout.write(self.style.SUCCESS(f"=== 결과: {absent_created}명 결석 처리 및 알림 발송 완료 ==="))