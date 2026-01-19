"""
학생 엑셀 파일 일괄 등록 명령어

사용법:
    py manage.py import_students 동탄 students_list_dongtan.xlsx

컬럼 순서:
    구문담당선생님 | 구문수업요일 | 구문시간 | 독해담당선생님 | 독해수업요일 | 독해시간 | 
    학생등원퇴원여부 | 이름 | 학교 | 학년 | 학생전화번호 | 엄마전화번호 | 아빠전화번호
"""
from django.core.management.base import BaseCommand
from django.contrib.auth.models import User
from core.models import StudentProfile, StaffProfile, Branch, School, ClassTime
import openpyxl
import re
import datetime
from datetime import time


class Command(BaseCommand):
    help = '엑셀 파일에서 학생 정보를 일괄 등록합니다.'

    def add_arguments(self, parser):
        parser.add_argument('branch', type=str, help='분원 이름 (예: 동탄)')
        parser.add_argument('file', type=str, help='엑셀 파일 경로')
        parser.add_argument('--dry-run', action='store_true', help='실제 저장 없이 미리보기')

    def handle(self, *args, **options):
        branch_name = options['branch']
        file_path = options['file']
        dry_run = options['dry_run']

        # 1. 분원 조회/생성
        branch, created = Branch.objects.get_or_create(name=branch_name)
        if created:
            self.stdout.write(self.style.SUCCESS(f'✅ 분원 생성: {branch_name}'))
        else:
            self.stdout.write(f'📍 분원 사용: {branch_name}')

        # 2. 파일 읽기 (Excel or CSV)
        if file_path.endswith('.csv'):
            import csv
            try:
                # CSV 파일 읽기 (UTF-8 w/ BOM 처리 가능)
                with open(file_path, 'r', encoding='utf-8-sig') as f:
                    reader = csv.reader(f)
                    # 헤더 건너뛰기
                    next(reader, None)
                    rows = list(reader)
            except Exception as e:
                self.stdout.write(self.style.ERROR(f'❌ CSV 파일 읽기 실패: {e}'))
                return
        else:
            # 엑셀 파일 읽기
            try:
                wb = openpyxl.load_workbook(file_path)
                ws = wb.active
                # 헤더 건너뛰기 (min_row=2)
                rows = list(ws.iter_rows(min_row=2, values_only=True))
            except Exception as e:
                self.stdout.write(self.style.ERROR(f'❌ 엑셀 파일 읽기 실패: {e}'))
                return

        self.stdout.write(f'📊 총 {len(rows)}개 행 발견')

        created_count = 0
        updated_count = 0
        skipped_count = 0

        for row_idx, row in enumerate(rows, start=2):
            try:
                result = self.process_row(row, branch, dry_run, row_idx)
                if result == 'created':
                    created_count += 1
                elif result == 'updated':
                    updated_count += 1
                else:
                    skipped_count += 1
            except Exception as e:
                self.stdout.write(self.style.WARNING(f'⚠️ 행 {row_idx} 오류: {e}'))
                skipped_count += 1

        # 4. 결과 출력
        self.stdout.write('')
        self.stdout.write(self.style.SUCCESS(f'=== 완료 ==='))
        self.stdout.write(f'  ✅ 생성: {created_count}명')
        self.stdout.write(f'  🔄 업데이트: {updated_count}명')
        self.stdout.write(f'  ⏭️ 스킵: {skipped_count}개')
        
        if dry_run:
            self.stdout.write(self.style.WARNING('⚡ DRY-RUN 모드: 실제 저장되지 않았습니다.'))

    def process_row(self, row, branch, dry_run, row_idx):
        """한 행 처리"""
        # 컬럼 매핑 (0-indexed) based on actual headers:
        # 0:담당선생님, 1:수업요일, 2:수업시간, 3:독해선생님, 4:독해수업요일, 5:독해수업시간
        # 6:입/퇴원, 7:학생이름, 8:학교, 9:학년, 10:수업시작일, 11:학생 H.P, 
        # 12:아버지, 13:아버지 H.P, 14:어머니, 15:어머니 H.P

        syntax_teacher_name = self.clean_str(row[0])
        syntax_day = self.clean_str(row[1])
        syntax_time = self.clean_str(row[2])
        reading_teacher_name = self.clean_str(row[3])
        reading_day = self.clean_str(row[4])
        reading_time = self.clean_str(row[5])
        
        status = self.clean_str(row[6])  # 입학/퇴원
        name = self.clean_str(row[7])
        school_name = self.clean_str(row[8])
        grade_str = self.clean_str(row[9])
        
        start_date_val = row[10] # 날짜 객체일 수 있음
        student_phone = self.clean_phone(row[11])
        # row[12] 아버지 이름 스킵
        dad_phone = self.clean_phone(row[13])
        # row[14] 어머니 이름 스킵
        mom_phone = self.clean_phone(row[15])

        if not name:
            return 'skipped'

        # 전화번호가 없으면 가짜 번호 생성 (필수 필드)
        if not student_phone:
            # 이름 + 분원으로 고유 번호 생성 시도? 아니면 스킵?
            # 일단 경고하고 스킵
            if dry_run:
                print(f"  ⚠️ [SKIP] {name}: 전화번호 없음")
            return 'skipped'

        # 시작일 처리
        start_date = None
        if start_date_val:
            if isinstance(start_date_val, (datetime.date, datetime.datetime)):
                start_date = start_date_val
            else:
                # 문자열이면 파싱 시도 (생략 가능)
                pass

        # 활성 상태
        is_active = (status == '입학')

        # 학년 파싱
        grade = self.parse_grade(grade_str)

        # School 조회/생성
        school = None
        if school_name:
            # grade_type, branch 필드 없음
            school, created = School.objects.get_or_create(name=school_name)
            if created:
                # branches M2M 필드에 분원 추가
                school.branches.add(branch)
            elif not school.branches.filter(id=branch.id).exists():
                school.branches.add(branch)

        # 선생님 조회/생성
        syntax_teacher = self.get_or_create_teacher(syntax_teacher_name, branch, is_syntax=True) if syntax_teacher_name else None
        reading_teacher = self.get_or_create_teacher(reading_teacher_name, branch, is_reading=True) if reading_teacher_name else None

        # 시간표 조회/생성
        syntax_class = self.get_or_create_class_time(syntax_day, syntax_time, branch, '구문') if syntax_day and syntax_time else None
        reading_class = self.get_or_create_class_time(reading_day, reading_time, branch, '독해') if reading_day and reading_time else None

        if dry_run:
            self.stdout.write(f'  [DRY] {name} ({student_phone}) - {school_name} {grade_str}')
            return 'created'

        # 유저 조회/생성 (전화번호 전체 = 아이디)
        # [FIX] 전화번호 전체(숫자만)를 아이디로 사용
        username = student_phone  
        user, user_created = User.objects.get_or_create(
            username=username,
            defaults={'is_active': is_active}
        )
        if not user_created:
            user.is_active = is_active
            user.save(update_fields=['is_active'])

        # 학생 프로필 조회/생성
        profile, profile_created = StudentProfile.objects.get_or_create(
            user=user,
            defaults={
                'name': name,
                'branch': branch,
                'school': school,
                'base_grade': grade,
                'phone_number': student_phone,
                'parent_phone_mom': mom_phone,
                'parent_phone_dad': dad_phone,
                'syntax_teacher': syntax_teacher,
                'reading_teacher': reading_teacher,
                'syntax_class': syntax_class,
                'reading_class': reading_class,
                'start_date': start_date or datetime.date.today(), # [NEW]
            }
        )

        if not profile_created:
            # 업데이트
            profile.name = name
            profile.branch = branch
            profile.school = school
            profile.base_grade = grade
            profile.phone_number = student_phone
            profile.parent_phone_mom = mom_phone
            profile.parent_phone_dad = dad_phone
            profile.syntax_teacher = syntax_teacher
            profile.reading_teacher = reading_teacher
            profile.syntax_class = syntax_class
            profile.reading_class = reading_class
            if start_date: # [NEW] 엑셀에 날짜 있으면 업데이트
                profile.start_date = start_date
            profile.save()
            self.stdout.write(f'  🔄 업데이트: {name}')
            return 'updated'
        else:
            self.stdout.write(self.style.SUCCESS(f'  ✅ 생성: {name} ({username})'))
            return 'created'

    def clean_str(self, value):
        """빈 문자열 처리"""
        if value is None:
            return ''
        return str(value).strip()

    def clean_phone(self, value):
        """전화번호 정제 (숫자만)"""
        if value is None:
            return ''
        return re.sub(r'[^0-9]', '', str(value))

    def parse_grade(self, grade_str):
        """학년 문자열을 숫자로 변환"""
        grade_map = {
            '초1': 1, '초2': 2, '초3': 3, '초4': 4, '초5': 5, '초6': 6,
            '중1': 7, '중2': 8, '중3': 9,
            '고1': 10, '고2': 11, '고3': 12,
            '졸업': 13, '성인': 13, '재수': 13
        }
        return grade_map.get(grade_str, 7)  # 기본값: 중1

    def infer_school_type(self, grade_str):
        """학년에서 학교 유형 추론"""
        if grade_str and grade_str.startswith('초'):
            return 'ELEMENTARY'
        elif grade_str and grade_str.startswith('중'):
            return 'MIDDLE'
        else:
            return 'HIGH'

    def get_or_create_teacher(self, teacher_name, branch, is_syntax=False, is_reading=False):
        """선생님 조회/생성"""
        # "위승연T" → "위승연"
        clean_name = re.sub(r'[T선생님\s]', '', teacher_name).strip()
        if not clean_name:
            return None

        # StaffProfile에서 이름으로 조회
        staff = StaffProfile.objects.filter(name=clean_name, branch=branch).first()
        if staff:
            # 과목 플래그 업데이트
            if is_syntax and not staff.is_syntax_teacher:
                staff.is_syntax_teacher = True
                staff.save(update_fields=['is_syntax_teacher'])
            if is_reading and not staff.is_reading_teacher:
                staff.is_reading_teacher = True
                staff.save(update_fields=['is_reading_teacher'])
            return staff.user

        # 없으면 생성
        username = f'teacher_{clean_name}_{branch.name}'
        user, _ = User.objects.get_or_create(
            username=username,
            defaults={'is_staff': True, 'is_active': True}
        )
        staff, _ = StaffProfile.objects.get_or_create(
            user=user,
            defaults={
                'name': clean_name,
                'branch': branch,
                'is_syntax_teacher': is_syntax,
                'is_reading_teacher': is_reading,
            }
        )
        self.stdout.write(f'  👨‍🏫 선생님 생성: {clean_name}')
        return user

    def get_or_create_class_time(self, day_str, time_str, branch, class_type_prefix):
        """시간표 조회/생성"""
        # 요일 매핑
        day_map = {
            '월요일': 'Mon', '화요일': 'Tue', '수요일': 'Wed', 
            '목요일': 'Thu', '금요일': 'Fri', '토요일': 'Sat', '일요일': 'Sun',
            '월': 'Mon', '화': 'Tue', '수': 'Wed', '목': 'Thu', 
            '금': 'Fri', '토': 'Sat', '일': 'Sun'
        }
        day_code = day_map.get(day_str, day_str)

        # 시간 파싱 (5:30 → 17:30)
        try:
            parts = time_str.replace(':', '.').split('.')
            hour = int(parts[0])
            minute = int(parts[1]) if len(parts) > 1 else 0
            # 오후 시간 보정 (1~9시는 13~21시로)
            if hour <= 9:
                hour += 12
            start_time = time(hour, minute)
        except:
            start_time = time(18, 0)  # 기본값

        # 종료 시간 (2시간 후)
        end_hour = (start_time.hour + 2) % 24
        end_time = time(end_hour, start_time.minute)

        # ClassTime 조회/생성 (분원별로 이름이 같아도 따로 관리됨)
        name = f'{class_type_prefix} {day_code} {start_time.strftime("%H:%M")}'
        
        # day_of_week -> day 필드명 수정
        # end_time 필드 추가
        # [FIX] branch를 defaults가 아닌 lookup 조건에 포함
        class_time, created = ClassTime.objects.get_or_create(
            name=name,
            branch=branch,
            defaults={
                'day': day_code,       # day_of_week -> day
                'start_time': start_time,
                'end_time': end_time,  # Added end_time
                'class_type': 'SYNTAX' if class_type_prefix == '구문' else 'READING',
            }
        )
        if created:
            self.stdout.write(f'  🕐 시간표 생성: {name}')
        return class_time
