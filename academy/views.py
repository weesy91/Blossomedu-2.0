from django.shortcuts import render, get_object_or_404, redirect
from .models import TemporarySchedule, Textbook, ClassLog, ClassLogEntry
from django.utils import timezone
from django.contrib import messages
from django.contrib.auth.decorators import user_passes_test, login_required
from django.db.models import Q
from datetime import datetime, timedelta, time
from django.http import JsonResponse
from core.models import StudentProfile 
import json
import os
import re

# core 앱의 모델들
from core.models import StudentProfile, ClassTime
# 현재 앱(academy)의 모델들
from .models import Attendance, TemporarySchedule

# ==========================================
# [1] 선생님용 수업 관리 대시보드 (NEW!)
# ==========================================
@login_required
def class_management(request):
    """
    선생님이 보는 '오늘의 수업 현황' 대시보드
    (?date=2024-12-25 처럼 날짜 선택 가능)
    """
    # 1. 날짜 및 요일 계산
    date_str = request.GET.get('date')
    if date_str:
        try:
            target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            target_date = timezone.now().date()
    else:
        target_date = timezone.now().date()

    target_weekday = target_date.weekday()
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    target_day_code = weekday_map[target_weekday]

    # 2. 보강/일정 변경 스케줄 가져오기
    temp_schedules = TemporarySchedule.objects.filter(new_date=target_date).order_by('new_start_time')
    class_list = []
    
    # [보강] 처리
    for schedule in temp_schedules:
        if not request.user.is_superuser:
            if schedule.subject == 'SYNTAX' and schedule.student.syntax_teacher != request.user:
                continue
            elif schedule.subject == 'READING' and schedule.student.reading_teacher != request.user:
                continue
        
        attendance = Attendance.objects.filter(student=schedule.student.user, date=target_date).first()
        has_attended = attendance is not None
        attendance_status = attendance.status if attendance else 'NONE'
        
        class_log = ClassLog.objects.filter(student=schedule.student.user, date=target_date).first()
        status = '작성완료' if class_log else '미작성'
        
        class_list.append({
            'student': schedule.student,
            'subject': schedule.subject,
            'class_time': schedule.target_class,
            'start_time': schedule.new_start_time,
            'status': status,
            'is_extra': schedule.is_extra_class,
            'note': schedule.note,
            'schedule_id': schedule.id,
            'has_attended': has_attended,
            'attendance_status': attendance_status,
        })
    
    # 3. [정규 수업] + [추가 수업] 처리
    # (최적화를 위해 extra_class 관련 필드도 select_related에 추가했습니다)
    students = StudentProfile.objects.select_related(
        'syntax_class', 'reading_class', 'extra_class', 
        'user'
    ).all()
    
    for student in students:
        # 공통 데이터 조회 (출석, 일지)
        attendance = Attendance.objects.filter(student=student.user, date=target_date).first()
        has_attended = attendance is not None
        attendance_status = attendance.status if attendance else 'NONE'
        
        class_log = ClassLog.objects.filter(student=student.user, date=target_date).first()
        status = '작성완료' if class_log else '미작성'

        # 공통 데이터 딕셔너리
        item_base = {
            'student': student,
            'status': status,
            'is_extra': False,
            'note': '',
            'schedule_id': 0, # 정규/추가 수업은 schedule_id 0
            'has_attended': has_attended,
            'attendance_status': attendance_status,
        }

        # (1) 구문 수업 확인
        if student.syntax_class and student.syntax_class.day == target_day_code:
            if request.user.is_superuser or student.syntax_teacher == request.user:
                # 보강 리스트에 이미 있는지 확인
                if not any(item['student'].id == student.id and item['subject'] == 'SYNTAX' for item in class_list):
                    item = item_base.copy()
                    item.update({
                        'subject': 'SYNTAX',
                        'class_time': student.syntax_class,
                        'start_time': student.syntax_class.start_time,
                    })
                    class_list.append(item)

        # (2) 독해 수업 확인
        if student.reading_class and student.reading_class.day == target_day_code:
            if request.user.is_superuser or student.reading_teacher == request.user:
                if not any(item['student'].id == student.id and item['subject'] == 'READING' for item in class_list):
                    item = item_base.copy()
                    item.update({
                        'subject': 'READING',
                        'class_time': student.reading_class,
                        'start_time': student.reading_class.start_time,
                    })
                    class_list.append(item)

        # (3) [NEW!] 추가 수업(Extra Class) 확인 (이 부분이 중요합니다!)
        if student.extra_class and student.extra_class.day == target_day_code:
            # 담당 선생님 체크 (extra_class_teacher)
            if request.user.is_superuser or student.extra_class_teacher == request.user:
                # 추가 수업은 보강 리스트 중복 체크 불필요 (보통 별도로 운영되므로)
                
                # 화면에 보여줄 이름: "구문 (추가)" 또는 "독해 (추가)"
                label = f"{student.get_extra_class_type_display()} (추가)"
                
                item = item_base.copy()
                item.update({
                    'subject': label,
                    'subject_code': student.extra_class_type, # DB 저장용 코드
                    'class_time': student.extra_class,
                    'start_time': student.extra_class.start_time,
                    'is_extra': True, # 추가 수업임을 표시
                })
                class_list.append(item)

    # 시간순 정렬
    class_list.sort(key=lambda x: x['start_time'] if x['start_time'] else time(23, 59))

    return render(request, 'academy/class_management.html', {
        'target_date': target_date,
        'class_list': class_list,
    })

# ==========================================
# [2] 원장님용 일일 총괄 대시보드
# ==========================================
@user_passes_test(lambda u: u.is_superuser)
def director_dashboard(request):
    """
    원장님(슈퍼유저)만 접근 가능한 일일 총괄 대시보드
    오늘 수업이 예정된 모든 학생의 출석 현황, 일지 작성 여부, 보강 여부를 한눈에 파악
    """
    # 1. 오늘 날짜와 요일 구하기
    today = timezone.now().date()
    # today_weekday = today.weekday()  # (필요 시 사용)
    
    # 요일을 ClassTime의 day 형식으로 변환 (Mon, Tue, ...)
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    today_day_code = weekday_map[today.weekday()]
    
    # [수정 Point 1] 필터링 조건에 '추가 수업(extra_class)' 포함
    students = StudentProfile.objects.select_related(
        'syntax_class', 'reading_class', 'extra_class', 'user'
    ).filter(
        Q(syntax_class__day=today_day_code) | 
        Q(reading_class__day=today_day_code) |
        Q(extra_class__day=today_day_code)
    ).distinct()
    
    # 3. 대시보드 데이터 리스트 생성
    dashboard_data = []
    
    for student in students:
        # 공통: 오늘 출석 정보 가져오기
        attendance = Attendance.objects.filter(student=student.user, date=today).first()
        
        # 출석 상태 뱃지 결정 (로직 단순화 및 통일)
        if attendance:
            status_code = attendance.status
        else:
            # 아직 등원 안 했으면 시간 비교
            # (지각 판단을 위해 가장 빠른 수업 시간을 구함)
            # 주의: _get_today_class_start_time 함수가 views.py 내부에 있어야 함.
            # 없다면 직접 계산 로직을 넣어야 하지만, 위에서 만든 helper 함수 활용 권장
            start_time = _get_today_class_start_time(student)
            if start_time and timezone.now().time() > start_time:
                status_code = 'NONE' # 시간 지남 (결석 유력)
            else:
                status_code = 'PENDING' # 수업 전

        # 공통 함수: 일지 작성 여부 확인
        def check_log(subj_type):
            # 추가 수업의 경우 subj_type에 SYNTAX/READING 코드가 들어옴
            # 정규 수업은 직접 문자열로 넣음
            return ClassLog.objects.filter(student=student.user, subject=subj_type, date=today).exists()

        # 1. [구문] 수업 데이터
        if student.syntax_class and student.syntax_class.day == today_day_code:
            t_name = student.syntax_teacher.username if student.syntax_teacher else "미지정"
            if student.syntax_teacher and hasattr(student.syntax_teacher, 'profile'):
                 t_name = student.syntax_teacher.profile.name

            dashboard_data.append({
                'student': student,
                'subject': '구문',
                'time': student.syntax_class,
                'teacher_name': t_name,
                'attendance_status': status_code,
                'log_status': check_log('SYNTAX'),
                'makeup_status': None # 보강 로직은 복잡하니 일단 None (필요시 추가)
            })

        # 2. [독해] 수업 데이터
        if student.reading_class and student.reading_class.day == today_day_code:
            t_name = student.reading_teacher.username if student.reading_teacher else "미지정"
            if student.reading_teacher and hasattr(student.reading_teacher, 'profile'):
                 t_name = student.reading_teacher.profile.name

            dashboard_data.append({
                'student': student,
                'subject': '독해',
                'time': student.reading_class,
                'teacher_name': t_name,
                'attendance_status': status_code,
                'log_status': check_log('READING'),
                'makeup_status': None
            })

        # 3. [수정 Point 2] [추가 수업] 데이터 (New!)
        if student.extra_class and student.extra_class.day == today_day_code:
            t_name = student.extra_class_teacher.username if student.extra_class_teacher else "미지정"
            if student.extra_class_teacher and hasattr(student.extra_class_teacher, 'profile'):
                 t_name = student.extra_class_teacher.profile.name
            
            # 화면 표시용 라벨 (예: "구문 (추가)")
            label = f"{student.get_extra_class_type_display()} (추가)"
            
            dashboard_data.append({
                'student': student,
                'subject': label,
                'time': student.extra_class,
                'teacher_name': t_name,
                'attendance_status': status_code,
                'log_status': check_log(student.extra_class_type), # SYNTAX or READING
                'makeup_status': None
            })

    # 시간순 정렬
    dashboard_data.sort(key=lambda x: x['time'].start_time if x['time'] else time(23, 59))
    
    return render(request, 'academy/director_dashboard.html', {
        'dashboard_data': dashboard_data,
        'today': today
    })

# ==========================================
# [2] 학생용 등원 키오스크 (EXISTING)
# ==========================================
# academy/views.py

def attendance_kiosk(request):
    if request.method == 'POST':
        # 1. 입력값 가져오기 (공백 제거 기능 추가!)
        raw_code = request.POST.get('attendance_code', '')
        code = raw_code.strip() # 앞뒤 공백 제거
        
        # 📢 [디버깅 로그] 터미널에서 이 줄을 확인하세요!
        print(f"\n======== [키오스크 디버깅] ========")
        print(f"1. 입력된 값(Raw): '{raw_code}'")
        print(f"2. 검색할 값(Clean): '{code}'")

        # 2. 번호로 학생 찾기
        profiles = StudentProfile.objects.filter(attendance_code=code)
        
        # 📢 [디버깅 로그]
        print(f"3. 검색된 학생 수: {profiles.count()}명")
        if profiles.exists():
            print(f"4. 찾은 학생 이름: {[p.name for p in profiles]}")
        else:
            print(f"4. ❌ 검색 실패! (DB에 '{code}'를 가진 학생이 없음)")
        print(f"==================================\n")

        if not profiles.exists():
            messages.error(request, '등록되지 않은 번호입니다.')
            return render(request, 'academy/kiosk.html')
        
        profile = profiles.first()
        today = timezone.now().date()
        now = timezone.now()
        
        # 3. 이미 등원했는지 확인
        if Attendance.objects.filter(student=profile.user, date=today).exists():
            log = Attendance.objects.filter(student=profile.user, date=today).first()
            messages.info(request, f"{profile.name} 학생, 이미 등원 처리되어 있습니다. ({log.get_status_display()})")
            return render(request, 'academy/kiosk.html', {'status': log.status})

        # 4. 시간 판별 로직
        earliest_start = _get_today_class_start_time(profile)
        status = 'PRESENT'
        msg_text = ""
        
        if earliest_start is None:
            status = 'PRESENT'
            msg_text = f"{profile.name} 학생 등원했습니다. (수업 없음)"
        else:
            class_start_datetime = datetime.combine(today, earliest_start)
            if timezone.is_aware(now):
                class_start_datetime = timezone.make_aware(class_start_datetime)
            
            limit_time = class_start_datetime + timedelta(minutes=40)

            if now < class_start_datetime:
                status = 'PRESENT'
            elif now <= limit_time:
                status = 'LATE'
            else:
                status = 'ABSENT'
                
            if status == 'PRESENT':
                msg_text = f"{profile.name} 학생 등원했습니다. (정상 출석)"
            elif status == 'LATE':
                msg_text = f"{profile.name} 학생 등원했습니다. (지각 처리됨)"
            else:
                msg_text = f"{profile.name} 학생 등원했습니다. (수업 시간 40분 초과 - 결석 처리)"

        # 5. DB 저장 (check_in_time 필드명 주의)
        Attendance.objects.create(
            student=profile.user, 
            date=today, 
            check_in_time=now, 
            status=status
        )
        
        if status == 'PRESENT':
            messages.success(request, msg_text)
        elif status == 'LATE':
            messages.warning(request, msg_text)
        else:
            messages.error(request, msg_text)

        return render(request, 'academy/kiosk.html', {'status': status})

    return render(request, 'academy/kiosk.html')

# ==========================================
# [3] 내부 로직 함수들 (Helper Functions)
# ==========================================
def _get_today_class_start_time(student_profile):
    """
    오늘 이 학생의 '기준 등원 시간'을 계산하는 핵심 함수
    우선순위: 1.보강(오늘로 변경된 것) -> 2.정규수업/추가수업 중 가장 빠른 것
    """
    today = timezone.now().date()
    today_weekday = today.weekday()
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    today_day_code = weekday_map[today_weekday]
    
    # 1. [1순위] 보강/일정 변경 확인
    temp_schedule = TemporarySchedule.objects.filter(
        student=student_profile,
        new_date=today
    ).first()
    
    if temp_schedule:
        return temp_schedule.new_start_time

    # 2. [예외] 오늘 원래 있던 수업이 딴 날로 도망갔는지 확인
    # (주의: 추가 수업은 고정 스케줄이므로 TemporarySchedule 로직에 보통 포함되지 않으나, 필요시 확장 가능)
    moved_away = TemporarySchedule.objects.filter(
        student=student_profile,
        original_date=today
    ).exists()
    
    if moved_away:
        # 보강이 잡혀있지 않은데 원래 수업만 이동했다면, 정규 수업은 없는 셈
        # 하지만 '추가 수업'은 남아있을 수 있으므로 아래 로직 계속 진행
        pass

    # 3. [2순위] 정규 수업 & 추가 수업 시간 확인
    start_times = []
    
    # (1) 구문 수업
    if student_profile.syntax_class and student_profile.syntax_class.day == today_day_code:
        # 만약 구문 수업이 이동되었다면 제외
        is_syntax_moved = TemporarySchedule.objects.filter(
            student=student_profile, original_date=today, subject='SYNTAX'
        ).exists()
        if not is_syntax_moved:
            start_times.append(student_profile.syntax_class.start_time)
        
    # (2) 독해 수업
    if student_profile.reading_class and student_profile.reading_class.day == today_day_code:
        # 만약 독해 수업이 이동되었다면 제외
        is_reading_moved = TemporarySchedule.objects.filter(
            student=student_profile, original_date=today, subject='READING'
        ).exists()
        if not is_reading_moved:
            start_times.append(student_profile.reading_class.start_time)

    # (3) 추가 수업 (New!)
    if student_profile.extra_class and student_profile.extra_class.day == today_day_code:
        start_times.append(student_profile.extra_class.start_time)
        
    if start_times:
        return min(start_times) # 가장 빠른 시간 리턴
        
    return None # 수업 없음


def _process_attendance(request, profile):
    """
    출석 처리 및 상태 판정 (40분 룰 적용)
    """
    # #region agent log
    log_path = r'c:\Users\Blossomedu동탄_02\Desktop\vocab_project\.cursor\debug.log'
    try:
        with open(log_path, 'a', encoding='utf-8') as f:
            import json
            f.write(json.dumps({
                'location': 'academy/views.py:_process_attendance',
                'message': 'Function entry',
                'data': {
                    'profile_type': str(type(profile)),
                    'profile_str': str(profile),
                    'profile_id': profile.id if hasattr(profile, 'id') else None,
                    'has_user': hasattr(profile, 'user'),
                    'user_type': str(type(profile.user)) if hasattr(profile, 'user') else None,
                },
                'timestamp': int(timezone.now().timestamp() * 1000),
                'sessionId': 'debug-session',
                'runId': 'run1',
                'hypothesisId': 'A'
            }, ensure_ascii=False) + '\n')
    except Exception as e:
        pass
    # #endregion
    
    # profile은 StudentProfile 객체
    now = timezone.now()
    today = now.date()
    current_time = now.time()

    # #region agent log
    try:
        with open(log_path, 'a', encoding='utf-8') as f:
            import json
            f.write(json.dumps({
                'location': 'academy/views.py:_process_attendance',
                'message': 'Before Attendance.objects.get_or_create',
                'data': {
                    'profile_type': str(type(profile)),
                    'profile_user_type': str(type(profile.user)) if hasattr(profile, 'user') else None,
                    'profile_user_id': profile.user.id if hasattr(profile, 'user') else None,
                },
                'timestamp': int(timezone.now().timestamp() * 1000),
                'sessionId': 'debug-session',
                'runId': 'run1',
                'hypothesisId': 'B'
            }, ensure_ascii=False) + '\n')
    except Exception as e:
        pass
    # #endregion

    # 1. 이미 출석했는지 확인 (Attendance.student는 User를 참조)
    attendance, created = Attendance.objects.get_or_create(
        student=profile.user,  # User 객체 사용
        date=today
    )
    
    if not created:
        messages.info(request, f"ℹ️ {profile.name} 학생은 이미 처리되었습니다. ({attendance.get_status_display()})")
        return

    # 2. 학생의 오늘 수업 중 가장 빠른 수업 시작 시간 찾기
    earliest_start_time = _get_today_class_start_time(profile)
    
    # 등원 시간 기록
    attendance.arrived_at = now
    
    # 3. 수업 시작 시간과 현재 시간 비교하여 상태 결정
    if earliest_start_time is None:
        # 오늘 수업이 없는 경우 -> PRESENT로 처리
        attendance.status = 'PRESENT'
        msg = f"✅ {profile.name} 학생 등원했습니다. (정상 출석)"
    else:
        # 시간 계산을 위해 datetime 객체로 변환
        class_datetime = datetime.combine(today, earliest_start_time)
        arrival_datetime = datetime.combine(today, current_time)
        
        # 차이 계산 (분 단위, 양수면 늦은 것)
        diff_minutes = (arrival_datetime - class_datetime).total_seconds() / 60
        
        # Case A: now < start (수업 전) -> PRESENT
        if diff_minutes < 0:
            attendance.status = 'PRESENT'
            msg = f"✅ {profile.name} 학생 등원했습니다. (정상 출석)"
        
        # Case B: start <= now <= start + 40분 -> LATE
        elif 0 <= diff_minutes <= 40:
            attendance.status = 'LATE'
            msg = f"⚠️ {profile.name} 학생 등원했습니다. (지각 처리됨)"
        
        # Case C: now > start + 40분 -> ABSENT
        else:
            attendance.status = 'ABSENT'
            msg = f"❌ {profile.name} 학생 등원했습니다. (수업 시간 40분 초과 - 결석 처리)"

    # 4. Attendance 객체 저장
    attendance.save()
    
    # 5. 메시지 표시
    if attendance.status == 'PRESENT':
        messages.success(request, msg)
    elif attendance.status == 'LATE':
        messages.warning(request, msg)
    else:
        messages.error(request, msg)


#### 수업일지관련####
def create_class_log(request, schedule_id):
    # #region agent log
    log_path = r'c:\Users\Blossomedu동탄_02\Desktop\vocab_project\.cursor\debug.log'
    try:
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps({
                'location': 'views.py:186',
                'message': 'create_class_log entry',
                'data': {'method': request.method, 'schedule_id': schedule_id},
                'timestamp': int(timezone.now().timestamp() * 1000),
                'sessionId': 'debug-session',
                'runId': 'run1',
                'hypothesisId': 'A'
            }, ensure_ascii=False) + '\n')
    except: pass
    # #endregion
    
    # 1. subject 파라미터 가져오기 (구문/독해 구분)
    subject = request.GET.get('subject', '')
    
    # 2. 스케줄 또는 정규 수업 정보 가져오기
    student = None
    schedule = None
    target_date = None
    
    if schedule_id == 0:
        # 정규 수업의 경우 (schedule_id가 0이면 student_id와 date를 사용)
        student_id = request.GET.get('student_id')
        date_str = request.GET.get('date')
        
        if student_id and date_str:
            from django.contrib.auth import get_user_model
            User = get_user_model()
            student = get_object_or_404(User, id=student_id)
            try:
                target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            except ValueError:
                target_date = timezone.now().date()
        else:
            from django.http import Http404
            raise Http404("정규 수업의 경우 student_id와 date가 필요합니다.")
    else:
        # 보강/일정 변경의 경우
        schedule = get_object_or_404(TemporarySchedule, id=schedule_id)
        student = schedule.student.user
        target_date = schedule.new_date
        # subject가 없으면 schedule에서 가져오기
        if not subject:
            subject = schedule.subject
    
    # 3. 교재 목록 가져오기
    # (1) 단어장: WordBook에서 가져오기 (vocab 앱) - 항상 표시
    from vocab.models import WordBook
    vocab_books = WordBook.objects.select_related('publisher').all()
    
    # (2) 주교재: 구문과 독해 교재 모두 표시 (과목 선택은 사용자가 직접)
    syntax_books = Textbook.objects.filter(category='SYNTAX')
    reading_books = Textbook.objects.filter(category='READING')
    grammar_books = Textbook.objects.filter(category='GRAMMAR')

    # POST 요청 처리 (데이터 저장)
    if request.method == 'POST':
        # #region agent log
        try:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps({
                    'location': 'views.py:210',
                    'message': 'POST request received',
                    'data': {
                        'post_keys': list(request.POST.keys()),
                        'vocab_book_ids': request.POST.getlist('vocab_book_ids[]'),
                        'vocab_ranges': request.POST.getlist('vocab_ranges[]'),
                        'main_book_ids': request.POST.getlist('main_book_ids[]'),
                        'main_ranges': request.POST.getlist('main_ranges[]'),
                    },
                    'timestamp': int(timezone.now().timestamp() * 1000),
                    'sessionId': 'debug-session',
                    'runId': 'run1',
                    'hypothesisId': 'B'
                }, ensure_ascii=False) + '\n')
        except: pass
        # #endregion
        
        # ClassLog 가져오기 또는 생성 (같은 날짜, 같은 학생의 일지가 있으면 업데이트)
        class_log, created = ClassLog.objects.get_or_create(
        student=student,
        date=target_date,
        subject=subject,  # <--- ⭐ 이 줄이 반드시 추가되어야 합니다!
        defaults={
            'teacher': request.user,
            'comment': request.POST.get('comment', '')
        }
    )
        
        # 기존 일지가 있으면 업데이트
        if not created:
            class_log.teacher = request.user
            class_log.comment = request.POST.get('comment', '')
            # 다음 과제 범위와 선생님 코멘트 업데이트
            next_hw_start = request.POST.get('next_hw_start', '').strip()
            next_hw_end = request.POST.get('next_hw_end', '').strip()
            class_log.next_hw_start = int(next_hw_start) if next_hw_start else None
            class_log.next_hw_end = int(next_hw_end) if next_hw_end else None
            class_log.teacher_comment = request.POST.get('teacher_comment', '')
            class_log.save()
            # 기존 항목들 삭제 (새로 입력한 내용으로 대체)
            class_log.entries.all().delete()
        else:
            # 새로 생성된 경우에도 다음 과제 범위와 선생님 코멘트 저장
            next_hw_start = request.POST.get('next_hw_start', '').strip()
            next_hw_end = request.POST.get('next_hw_end', '').strip()
            class_log.next_hw_start = int(next_hw_start) if next_hw_start else None
            class_log.next_hw_end = int(next_hw_end) if next_hw_end else None
            class_log.teacher_comment = request.POST.get('teacher_comment', '')
            class_log.save()
        
        # #region agent log
        try:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps({
                    'location': 'views.py:230',
                    'message': 'ClassLog created',
                    'data': {'class_log_id': class_log.id},
                    'timestamp': int(timezone.now().timestamp() * 1000),
                    'sessionId': 'debug-session',
                    'runId': 'run1',
                    'hypothesisId': 'A'
                }, ensure_ascii=False) + '\n')
        except: pass
        # #endregion
        
        # 단어장(vocab) 섹션 - 여러 개 처리
        vocab_book_ids = request.POST.getlist('vocab_book_ids[]')
        vocab_ranges = request.POST.getlist('vocab_ranges[]')
        vocab_scores = request.POST.getlist('vocab_scores[]')
        
        # #region agent log
        try:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps({
                    'location': 'views.py:238',
                    'message': 'Before vocab processing',
                    'data': {
                        'vocab_book_ids_count': len(vocab_book_ids),
                        'vocab_ranges_count': len(vocab_ranges),
                        'vocab_scores_count': len(vocab_scores),
                    },
                    'timestamp': int(timezone.now().timestamp() * 1000),
                    'sessionId': 'debug-session',
                    'runId': 'run1',
                    'hypothesisId': 'E'
                }, ensure_ascii=False) + '\n')
        except: pass
        # #endregion
        
        vocab_entries_created = 0
        for i in range(len(vocab_book_ids)):
            vocab_book_id = vocab_book_ids[i].strip()
            vocab_range = vocab_ranges[i].strip() if i < len(vocab_ranges) else ''
            vocab_score = vocab_scores[i].strip() if i < len(vocab_scores) else ''
            
            # #region agent log
            try:
                with open(log_path, 'a', encoding='utf-8') as f:
                    f.write(json.dumps({
                        'location': 'views.py:250',
                        'message': 'Vocab entry check',
                        'data': {
                            'index': i,
                            'vocab_book_id': vocab_book_id,
                            'vocab_range': vocab_range,
                            'will_create': bool(vocab_book_id and vocab_range)
                        },
                        'timestamp': int(timezone.now().timestamp() * 1000),
                        'sessionId': 'debug-session',
                        'runId': 'run1',
                        'hypothesisId': 'E'
                    }, ensure_ascii=False) + '\n')
            except: pass
            # #endregion
            
            # 단어장이 선택되고 범위가 입력된 경우만 저장
            if vocab_book_id and vocab_range:
                # 진도 범위 유효성 검사: 숫자 또는 범위 형식만 허용 (예: "5", "1-3")
                vocab_range = vocab_range.strip()
                if not re.match(r'^\d+(-\d+)?$', vocab_range):
                    continue  # 유효하지 않은 형식이면 건너뛰기
                
                wordbook = get_object_or_404(WordBook, id=vocab_book_id)
                ClassLogEntry.objects.create(
                    class_log=class_log,
                    wordbook=wordbook,
                    progress_range=vocab_range,
                    score=vocab_score if vocab_score else None
                )
                vocab_entries_created += 1
        
        # 진도 교재(main) 섹션 - 여러 개 처리
        main_book_ids = request.POST.getlist('main_book_ids[]')
        main_ranges = request.POST.getlist('main_ranges[]')
        main_scores = request.POST.getlist('main_scores[]')
        
        # #region agent log
        try:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps({
                    'location': 'views.py:278',
                    'message': 'Before main processing',
                    'data': {
                        'main_book_ids_count': len(main_book_ids),
                        'main_ranges_count': len(main_ranges),
                        'main_scores_count': len(main_scores),
                    },
                    'timestamp': int(timezone.now().timestamp() * 1000),
                    'sessionId': 'debug-session',
                    'runId': 'run1',
                    'hypothesisId': 'E'
                }, ensure_ascii=False) + '\n')
        except: pass
        # #endregion
        
        main_entries_created = 0
        for i in range(len(main_book_ids)):
            main_book_id = main_book_ids[i].strip()
            main_range = main_ranges[i].strip() if i < len(main_ranges) else ''
            main_score = main_scores[i].strip() if i < len(main_scores) else ''
            
            # #region agent log
            try:
                with open(log_path, 'a', encoding='utf-8') as f:
                    f.write(json.dumps({
                        'location': 'views.py:290',
                        'message': 'Main entry check',
                        'data': {
                            'index': i,
                            'main_book_id': main_book_id,
                            'main_range': main_range,
                            'will_create': bool(main_book_id and main_range)
                        },
                        'timestamp': int(timezone.now().timestamp() * 1000),
                        'sessionId': 'debug-session',
                        'runId': 'run1',
                        'hypothesisId': 'E'
                    }, ensure_ascii=False) + '\n')
            except: pass
            # #endregion
            
            # 교재가 선택되고 범위가 입력된 경우만 저장
            if main_book_id and main_range:
                # 진도 범위 유효성 검사: 숫자 또는 범위 형식만 허용 (예: "5", "3-7")
                main_range = main_range.strip()
                if not re.match(r'^\d+(-\d+)?$', main_range):
                    continue  # 유효하지 않은 형식이면 건너뛰기
                
                main_book = get_object_or_404(Textbook, id=main_book_id)
                
                ClassLogEntry.objects.create(
                    class_log=class_log,
                    textbook=main_book,
                    progress_range=main_range,
                    score=main_score if main_score else None
                )
                main_entries_created += 1
        
        # #region agent log
        try:
            with open(log_path, 'a', encoding='utf-8') as f:
                f.write(json.dumps({
                    'location': 'views.py:315',
                    'message': 'Entries created summary',
                    'data': {
                        'vocab_entries_created': vocab_entries_created,
                        'main_entries_created': main_entries_created
                    },
                    'timestamp': int(timezone.now().timestamp() * 1000),
                    'sessionId': 'debug-session',
                    'runId': 'run1',
                    'hypothesisId': 'A'
                }, ensure_ascii=False) + '\n')
        except: pass
        # #endregion
        
        # 플립러닝 과제 링크 조회 및 가상 문자 발송 로그 출력
        next_hw_start = request.POST.get('next_hw_start', '').strip()
        next_hw_end = request.POST.get('next_hw_end', '').strip()
        teacher_comment = request.POST.get('teacher_comment', '').strip()
        
        if next_hw_start and next_hw_end:
            try:
                hw_start = int(next_hw_start)
                hw_end = int(next_hw_end)
                
                # 학생 이름 가져오기
                student_name = student.profile.name if hasattr(student, 'profile') else student.username
                
                # 오늘 수업에서 사용한 교재들 확인 (main_book_ids에서)
                main_book_ids = request.POST.getlist('main_book_ids[]')
                
                for main_book_id in main_book_ids:
                    if not main_book_id.strip():
                        continue
                    
                    try:
                        textbook = Textbook.objects.get(id=main_book_id.strip())
                        # 해당 교재의 start~end 강 범위에 해당하는 링크들 조회
                        from .models import TextbookUnit
                        units = TextbookUnit.objects.filter(
                            textbook=textbook,
                            unit_number__gte=hw_start,
                            unit_number__lte=hw_end
                        ).order_by('unit_number')
                        
                        if units.exists():
                            # 가상 문자 발송 로그 출력
                            print("\n" + "="*60)
                            print("[가상 문자 발송 로그]")
                            print("="*60)
                            print(f"받는 사람: {student_name}")
                            print("내용:")
                            print(f'  "[과제 안내] {textbook.title} {hw_start}~{hw_end}강"')
                            print("  링크:")
                            link_urls = []
                            for unit in units:
                                if unit.link_url:
                                    link_urls.append(unit.link_url)
                                    print(f"    {unit.unit_number}강: {unit.link_url}")
                            if not link_urls:
                                print("    (링크 미등록)")
                            if teacher_comment:
                                print(f'  "코멘트: {teacher_comment}"')
                            else:
                                print('  "코멘트: (없음)"')
                            print("="*60 + "\n")
                    except Textbook.DoesNotExist:
                        continue
                        
            except ValueError:
                # 숫자 변환 실패 시 무시
                pass
        
        # 1. 과제 정보 가져오기
        hw_vocab_book_id = request.POST.get('hw_vocab_book_id')
        hw_vocab_range = request.POST.get('hw_vocab_range', '').strip()
        hw_main_book_id = request.POST.get('hw_main_book_id')
        hw_main_range = request.POST.get('hw_main_range', '').strip()
        
        # 2. 과제 정보 업데이트
        if hw_vocab_book_id:
            from vocab.models import WordBook
            class_log.hw_vocab_book = get_object_or_404(WordBook, id=hw_vocab_book_id)
        else:
            class_log.hw_vocab_book = None
            
        class_log.hw_vocab_range = hw_vocab_range
        
        if hw_main_book_id:
            class_log.hw_main_book = get_object_or_404(Textbook, id=hw_main_book_id)
        else:
            class_log.hw_main_book = None
            
        class_log.hw_main_range = hw_main_range
        
        # 선생님 코멘트도 업데이트
        class_log.teacher_comment = request.POST.get('teacher_comment', '')
        class_log.save()

        # 3. 알림 발송 로직 (체크박스 확인)
        should_send = request.POST.get('send_notification') == 'on'
        
        if should_send:
            # 아까 만든 함수 호출
            send_homework_notification(class_log)
            
            # 발송 시간 기록
            class_log.notification_sent_at = timezone.now()
            class_log.save()
            messages.success(request, "일지 저장 및 알림톡 발송이 완료되었습니다! 🚀")
        else:
            messages.success(request, "일지가 저장되었습니다. (알림 미발송)")

        # ========================================================
        
        # 저장 완료 후 대시보드로 리다이렉트
        return redirect('academy:class_management')
    
    # GET 요청 처리 (화면 보여주기)
    # 기존 일지가 있는지 확인 (같은 날짜, 같은 학생)
    existing_log = ClassLog.objects.filter(
        student=student,
        date=target_date
    ).first()
    
    # 기존 일지의 항목들 불러오기
    existing_vocab_entries = []
    existing_main_entries = []
    existing_comment = ''
    existing_next_hw_start = None
    existing_next_hw_end = None
    existing_teacher_comment = ''
    
    if existing_log:
        existing_comment = existing_log.comment
        existing_next_hw_start = existing_log.next_hw_start
        existing_next_hw_end = existing_log.next_hw_end
        existing_teacher_comment = existing_log.teacher_comment
        entries = existing_log.entries.all()
        for entry in entries:
            if entry.wordbook:
                # 단어장 항목
                existing_vocab_entries.append({
                    'wordbook_id': entry.wordbook.id,
                    'wordbook_title': entry.wordbook.title,
                    'publisher': entry.wordbook.publisher.name if entry.wordbook.publisher else '',
                    'range': entry.progress_range,
                    'score': entry.score or ''
                })
            elif entry.textbook:
                # 교재 항목
                existing_main_entries.append({
                    'textbook_id': entry.textbook.id,
                    'textbook_title': entry.textbook.title,
                    'category': entry.textbook.category,
                    'range': entry.progress_range,
                    'score': entry.score or ''
                })
    
    # #region agent log
    try:
        with open(log_path, 'a', encoding='utf-8') as f:
            f.write(json.dumps({
                'location': 'views.py:419',
                'message': 'GET request - rendering form',
                'data': {
                    'has_existing_log': existing_log is not None,
                    'vocab_entries_count': len(existing_vocab_entries),
                    'main_entries_count': len(existing_main_entries)
                },
                'timestamp': int(timezone.now().timestamp() * 1000),
                'sessionId': 'debug-session',
                'runId': 'run1',
                'hypothesisId': 'C'
            }, ensure_ascii=False) + '\n')
    except: pass
    # #endregion
    
    # 교재 데이터를 JSON으로 변환 (JavaScript에서 사용)
    import json as json_module
    syntax_books_json = json_module.dumps([{'id': b.id, 'title': b.title} for b in syntax_books])
    reading_books_json = json_module.dumps([{'id': b.id, 'title': b.title} for b in reading_books])
    grammar_books_json = json_module.dumps([{'id': b.id, 'title': b.title} for b in grammar_books])
    
    # 단어장(WordBook)을 출판사별로 그룹화
    vocab_publishers_set = set()
    vocab_books_by_publisher = {}
    for wordbook in vocab_books:
        publisher_name = wordbook.publisher.name if wordbook.publisher else ''
        if publisher_name:
            vocab_publishers_set.add(publisher_name)
            if publisher_name not in vocab_books_by_publisher:
                vocab_books_by_publisher[publisher_name] = []
            vocab_books_by_publisher[publisher_name].append({
                'id': wordbook.id,
                'title': wordbook.title
            })
    vocab_books_json = json_module.dumps(vocab_books_by_publisher)
    vocab_publishers_list = sorted(vocab_publishers_set)
    
    # 기존 데이터를 JSON으로 변환
    existing_vocab_entries_json = json_module.dumps(existing_vocab_entries, ensure_ascii=False)
    existing_main_entries_json = json_module.dumps(existing_main_entries, ensure_ascii=False)
    
    context = {
        'schedule': schedule,
        'student': student,
        'target_date': target_date,
        'subject': subject,
        'vocab_books': vocab_books,
        'vocab_publishers': vocab_publishers_list,
        'syntax_books': syntax_books,
        'reading_books': reading_books,
        'grammar_books': grammar_books,
        'vocab_books_json': vocab_books_json,
        'syntax_books_json': syntax_books_json,
        'reading_books_json': reading_books_json,
        'grammar_books_json': grammar_books_json,
        'existing_vocab_entries': existing_vocab_entries_json,
        'existing_main_entries': existing_main_entries_json,
        'existing_comment': existing_comment,
        'class_log': existing_log,  # 기존 일지 객체 (다음 과제 범위, 선생님 코멘트 표시용)
    }
    return render(request, 'academy/class_log_form.html', context)

#========부원장용 관리 대시보드

@login_required
def vice_dashboard(request):
    """
    부원장님 전용: 내 담당 강사들의 수업 및 일지 현황 확인
    """
    # 1. 권한 체크
    if not hasattr(request.user, 'staff_profile') or request.user.staff_profile.position != 'VICE':
        messages.error(request, "부원장 권한이 필요합니다.")
        return redirect('core:teacher_home')

    # 2. 날짜 선택
    date_str = request.GET.get('date')
    if date_str:
        try:
            target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError:
            target_date = timezone.now().date()
    else:
        target_date = timezone.now().date()

    # 3. 내 팀원(강사) 목록
    my_teachers = request.user.staff_profile.managed_teachers.all()
    
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    target_day_code = weekday_map[target_date.weekday()]
    
    # 4. 학생 조회
    students = StudentProfile.objects.filter(
        Q(syntax_teacher__in=my_teachers, syntax_class__day=target_day_code) |
        Q(reading_teacher__in=my_teachers, reading_class__day=target_day_code) |
        Q(extra_class_teacher__in=my_teachers, extra_class__day=target_day_code)
    ).distinct().select_related('user')

    dashboard_data = []

    for student in students:
        # ==========================================
        # 👇 [NEW] 출석 상태 판별 로직 추가
        # ==========================================
        attendance = Attendance.objects.filter(student=student.user, date=target_date).first()
        
        if attendance:
            status_code = attendance.status
        else:
            # 아직 등원 기록 없음 -> 지각 여부 판단
            start_time = _get_today_class_start_time(student) # (helper 함수 활용)
            
            # 오늘 날짜이고, 현재 시간이 수업 시작 시간을 지났다면 'NONE(결석/미등원)'으로 표시
            if target_date == timezone.now().date() and start_time and timezone.now().time() > start_time:
                status_code = 'NONE'
            else:
                status_code = 'PENDING' # 수업 전 or 미래 날짜
        # ==========================================

        # 공통 함수: 일지 작성 여부
        def check_log(subj_type, teacher_list):
            return ClassLog.objects.filter(
                student=student.user, 
                subject=subj_type, 
                date=target_date,
                teacher__in=teacher_list
            ).exists()
            
        # (1) 구문 수업
        if student.syntax_teacher in my_teachers and student.syntax_class and student.syntax_class.day == target_day_code:
             dashboard_data.append({
                'student': student,
                'subject': '구문',
                'time': student.syntax_class,
                'teacher': student.syntax_teacher,
                'log_status': check_log('SYNTAX', my_teachers),
                'attendance_status': status_code  # 👈 추가됨
            })

        # (2) 독해 수업
        if student.reading_teacher in my_teachers and student.reading_class and student.reading_class.day == target_day_code:
             dashboard_data.append({
                'student': student,
                'subject': '독해',
                'time': student.reading_class,
                'teacher': student.reading_teacher,
                'log_status': check_log('READING', my_teachers),
                'attendance_status': status_code  # 👈 추가됨
            })
            
        # (3) 추가 수업
        if student.extra_class_teacher in my_teachers and student.extra_class and student.extra_class.day == target_day_code:
             label = f"{student.get_extra_class_type_display()} (추가)"
             subj_code = student.extra_class_type
             dashboard_data.append({
                'student': student,
                'subject': label,
                'time': student.extra_class,
                'teacher': student.extra_class_teacher,
                'log_status': check_log(subj_code, my_teachers),
                'attendance_status': status_code  # 👈 추가됨
            })

    dashboard_data.sort(key=lambda x: x['time'].start_time if x['time'] else time(23, 59))

    return render(request, 'academy/vice_dashboard.html', {
        'target_date': target_date,
        'dashboard_data': dashboard_data,
        'my_teachers': my_teachers,
    })

@login_required
# [NEW] 보강 및 일정 변경 처리 뷰
def schedule_change(request, student_id):
    from .models import TemporarySchedule
    import json
    
    student = get_object_or_404(StudentProfile, id=student_id)
    initial_subject = request.GET.get('subject', 'SYNTAX') 

    # ==========================================
    # 🕒 [NEW] 정교한 시간표 생성 로직
    # ==========================================
    def generate_slots(start_str, end_str, interval_min):
        """시작시간, 종료시간(마지막수업 끝나는시간), 간격을 받아 시작시간 리스트 반환"""
        slots = []
        current = datetime.strptime(start_str, "%H:%M")
        end = datetime.strptime(end_str, "%H:%M")
        
        # current + interval이 end보다 작거나 같을 때까지 반복 (수업 시작 시간 기준)
        while current + timedelta(minutes=interval_min) <= end:
            slots.append(current.strftime("%H:%M"))
            current += timedelta(minutes=interval_min)
        # 딱 떨어지는 마지막 시간 처리 (위 조건에서 빠질 수 있으므로 확인)
        # 예: 21:20 종료면 마지막 시작시간은 20:40이어야 함
        return slots

    # 1. 평일 구문 (16:00 ~ 21:20 끝 / 40분 간격) -> 마지막 시작 20:40
    weekday_syntax = generate_slots("16:00", "21:21", 40) # 21:21로 넉넉히 잡음

    # 2. 평일 독해 (16:00 ~ 21:30 끝 / 30분 간격) -> 마지막 시작 21:00
    weekday_reading = generate_slots("16:00", "21:31", 30)

    # 3. 주말 구문 (오전 09:00~12:20 / 오후 13:20~18:40 / 40분 간격)
    weekend_syntax_am = generate_slots("09:00", "12:21", 40)
    weekend_syntax_pm = generate_slots("13:20", "18:41", 40)
    weekend_syntax = weekend_syntax_am + weekend_syntax_pm

    # 4. 주말 독해 (09:00 ~ 18:30 끝 / 30분 간격)
    weekend_reading = generate_slots("09:00", "18:31", 30)
    # ==========================================

    if request.method == 'POST':
        # (기존 저장 로직 동일)
        subject = request.POST.get('subject')
        new_date_str = request.POST.get('new_date')
        new_time_str = request.POST.get('new_time') 
        is_extra = request.POST.get('is_extra') == 'on'
        note = request.POST.get('note', '')

        try:
            new_date = datetime.strptime(new_date_str, '%Y-%m-%d').date()
            new_time = datetime.strptime(new_time_str, '%H:%M').time()
        except ValueError:
            messages.error(request, "날짜 또는 시간 형식이 올바르지 않습니다.")
            return redirect(request.path)

        TemporarySchedule.objects.create(
            student=student,
            subject=subject,
            new_date=new_date,
            new_start_time=new_time,
            is_extra_class=is_extra,
            note=note
        )
        msg_type = "보강" if is_extra else "일정 변경"
        messages.success(request, f"{student.name} 학생의 {subject} {msg_type}이 설정되었습니다.")
        return redirect('academy:class_management')

    return render(request, 'academy/schedule_change_form.html', {
        'student': student,
        'initial_subject': initial_subject,
        'today': timezone.now().date(),
        # 👇 4가지 케이스를 모두 JSON으로 전달
        'weekday_syntax_json': json.dumps(weekday_syntax),
        'weekday_reading_json': json.dumps(weekday_reading),
        'weekend_syntax_json': json.dumps(weekend_syntax),
        'weekend_reading_json': json.dumps(weekend_reading),
    })

def check_availability(request):
    """
    [AJAX API] 특정 날짜, 특정 학생(의 담당 선생님)의 예약된 시간 목록 반환
    """
    student_id = request.GET.get('student_id')
    subject = request.GET.get('subject') # 'SYNTAX' or 'READING'
    date_str = request.GET.get('date')

    if not (student_id and subject and date_str):
        return JsonResponse({'booked': []})

    try:
        target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        student = StudentProfile.objects.get(id=student_id)
        
        # 1. 담당 선생님 찾기
        teacher = student.syntax_teacher if subject == 'SYNTAX' else student.reading_teacher
        if not teacher:
            return JsonResponse({'booked': []})

        booked_times = set()
        
        # 2. [정규 수업] 체크: 해당 요일에 이 선생님 수업이 있는 학생들 찾기
        weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
        day_code = weekday_map[target_date.weekday()]
        
        # (1) 구문 수업이 있는 학생들
        syntax_students = StudentProfile.objects.filter(
            syntax_teacher=teacher, 
            syntax_class__day=day_code
        ).select_related('syntax_class')
        
        for s in syntax_students:
            # "원래 수업이 있었는데, 오늘 말고 다른 날로 변경한 경우"인지 체크
            is_moved = TemporarySchedule.objects.filter(
                student=s, 
                original_date=target_date, 
                subject='SYNTAX'
            ).exists()
            if not is_moved and s.syntax_class:
                booked_times.add(s.syntax_class.start_time.strftime('%H:%M'))

        # (2) 독해 수업이 있는 학생들
        reading_students = StudentProfile.objects.filter(
            reading_teacher=teacher, 
            reading_class__day=day_code
        ).select_related('reading_class')
        
        for s in reading_students:
            is_moved = TemporarySchedule.objects.filter(
                student=s, 
                original_date=target_date, 
                subject='READING'
            ).exists()
            if not is_moved and s.reading_class:
                booked_times.add(s.reading_class.start_time.strftime('%H:%M'))

        # 3. [보강/변경] 체크: 이 날짜에 새로 잡힌 스케줄 찾기
        # (TemporarySchedule에는 teacher 필드가 없으므로, 학생을 통해 선생님을 확인해야 함)
        # 간단하게: 오늘 날짜에 잡힌 모든 TemporarySchedule 중, 담당 쌤이 'teacher'인 것
        temp_schedules = TemporarySchedule.objects.filter(new_date=target_date)
        
        for schedule in temp_schedules:
            # 그 스케줄 학생의 해당 과목 담당 쌤이 'teacher'인지 확인
            s_teacher = None
            if schedule.subject == 'SYNTAX':
                s_teacher = schedule.student.syntax_teacher
            else:
                s_teacher = schedule.student.reading_teacher
            
            if s_teacher == teacher and schedule.new_start_time:
                booked_times.add(schedule.new_start_time.strftime('%H:%M'))

        # 리스트로 변환 및 정렬하여 반환
        return JsonResponse({'booked': sorted(list(booked_times))})

    except Exception as e:
        print(f"Error checking availability: {e}")
        return JsonResponse({'booked': []})
    

def get_occupied_times(request):
    """
    [Admin용 API] 특정 선생님이 이미 수업 중인 시간표 ID 목록 반환
    """
    teacher_id = request.GET.get('teacher_id')
    subject = request.GET.get('subject') # 'syntax', 'reading', 'extra'
    # URL에서 따온 ID는 'StudentUser(계정)'의 ID입니다.
    current_user_id = request.GET.get('current_student_id') 

    if not teacher_id or not subject:
        return JsonResponse({'occupied_ids': []})

    occupied_ids = []

    try:
        # 1. 과목에 따른 필드명 설정
        if subject == 'syntax':
            teacher_field = 'syntax_teacher'
            class_field = 'syntax_class'
        elif subject == 'reading':
            teacher_field = 'reading_teacher'
            class_field = 'reading_class'
        elif subject == 'extra':
            teacher_field = 'extra_class_teacher'  # ✅ 모델 필드명(extra_class_teacher)과 일치!
            class_field = 'extra_class'
        else:
            return JsonResponse({'occupied_ids': []})

        # 2. 기본 필터: 해당 선생님 담당 학생들 찾기
        filters = {teacher_field: teacher_id}
        qs = StudentProfile.objects.filter(**filters).exclude(
            **{f"{class_field}__isnull": True}
        )

        # 3. [중요] 수정 중인 학생 본인은 제외해야 함!
        # current_user_id(계정ID)를 이용해 Profile을 찾아서 제외
        if current_user_id and current_user_id.isdigit():
            qs = qs.exclude(user__id=int(current_user_id))

        # 4. 시간표 ID 리스트 추출
        occupied_ids = list(qs.values_list(class_field, flat=True))

        return JsonResponse({'occupied_ids': occupied_ids})

    except Exception as e:
        print(f"Error in get_occupied_times: {e}")
        return JsonResponse({'occupied_ids': []})
    
# academy/views.py 맨 아래

def send_homework_notification(class_log):
    """
    구성된 과제 정보를 바탕으로 카톡 메시지 생성 및 발송 (안전한 버전)
    """
    # 1. 학생 이름 가져오기 (안전장치 적용)
    # 학생 프로필(profile)이 있으면 이름 사용, 없으면 아이디 사용
    if hasattr(class_log.student, 'profile'):
        student_name = class_log.student.profile.name
    else:
        student_name = class_log.student.username
    
    # 2. 선생님 이름 가져오기 (안전장치 적용)
    # 선생님 프로필(staff_profile)이 있으면 이름 사용, 없으면 아이디 사용
    if class_log.teacher:
        if hasattr(class_log.teacher, 'staff_profile'):
            teacher_name = class_log.teacher.staff_profile.name
        elif hasattr(class_log.teacher, 'profile'): # 혹시 학생이 선생님일 경우
            teacher_name = class_log.teacher.profile.name
        else:
            teacher_name = class_log.teacher.username
    else:
        teacher_name = "담임 선생님"

    # 3. 메시지 구성
    message = f"[블라썸에듀] {student_name} 학생 오늘 수업 리포트\n\n"
    message += f"📅 수업일: {class_log.date}\n"
    message += f"🧑‍🏫 담당: {teacher_name}\n\n"
    
    message += "📝 [다음 과제 안내]\n"
    
    # 단어 과제
    if class_log.hw_vocab_book:
        message += f"📕 단어: {class_log.hw_vocab_book.title}\n"
        message += f"   └ 범위: {class_log.hw_vocab_range}\n"
        
    # 주교재 과제
    if class_log.hw_main_book:
        message += f"📘 진도: {class_log.hw_main_book.title}\n"
        message += f"   └ 범위: {class_log.hw_main_range}\n"
        
    # 코멘트
    if class_log.teacher_comment:
        message += f"\n💬 선생님 말씀:\n{class_log.teacher_comment}\n"
        
    message += "\n꼼꼼하게 준비해서 다음 수업 때 만나요! 💪"

    # 4. 실제 발송 (로그 출력)
    print(f"\n{'='*20} [카톡 발송] {'='*20}")
    print(message)
    print(f"{'='*50}\n")