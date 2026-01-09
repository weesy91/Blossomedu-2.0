from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required, user_passes_test
from django.contrib import messages
from django.utils import timezone
from django.db.models import Q, Max 
from datetime import datetime, time, timedelta

from core.models import StudentProfile
from academy.models import Attendance, TemporarySchedule, ClassLog
from academy.utils import get_today_class_start_time

def is_my_student(user, student):
    if user.is_superuser: return True
    if hasattr(user, 'staff_profile') and user.staff_profile.position == 'VICE':
        managed = user.staff_profile.managed_teachers.all()
        return (
            student.syntax_teacher == user or 
            student.reading_teacher == user or 
            student.extra_class_teacher == user or
            student.syntax_teacher in managed or
            student.reading_teacher in managed or
            student.extra_class_teacher in managed
        )
    return (
        student.syntax_teacher == user or 
        student.reading_teacher == user or 
        student.extra_class_teacher == user
    )

@login_required
def class_management(request):
    """선생님용 수업 관리"""
    date_str = request.GET.get('date')
    search_query = request.GET.get('q', '').strip()

    if date_str:
        try: target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError: target_date = timezone.now().date()
    else:
        target_date = timezone.now().date()

    action = request.GET.get('action')
    if action == 'prev': target_date -= timedelta(days=1)
    elif action == 'next': target_date += timedelta(days=1)

    target_weekday = target_date.weekday()
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    target_day_code = weekday_map[target_weekday]

    class_list = []

    # 1. 보강 스케줄
    temp_qs = TemporarySchedule.objects.filter(new_date=target_date).select_related('student')
    if search_query:
        temp_qs = temp_qs.filter(student__name__icontains=search_query)

    for schedule in temp_qs:
        if not is_my_student(request.user, schedule.student): continue
        
        attendance = Attendance.objects.filter(student=schedule.student, date=target_date).first()
        has_attended = attendance is not None
        attendance_status = attendance.status if attendance else 'NONE'
        class_log = ClassLog.objects.filter(student=schedule.student, date=target_date).first()
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
    
    # 2. 정규 수업
    student_qs = StudentProfile.objects.select_related('syntax_class', 'reading_class', 'extra_class').all()
    if search_query:
        student_qs = student_qs.filter(name__icontains=search_query)

    for student in student_qs:
        if not is_my_student(request.user, student): continue

        attendance = Attendance.objects.filter(student=student, date=target_date).first()
        has_attended = attendance is not None
        attendance_status = attendance.status if attendance else 'NONE'
        class_log = ClassLog.objects.filter(student=student, date=target_date).first()
        status = '작성완료' if class_log else '미작성'

        item_base = {
            'student': student, 'status': status, 'is_extra': False, 'note': '',
            'schedule_id': 0, 'has_attended': has_attended, 'attendance_status': attendance_status,
        }

        if student.syntax_class and student.syntax_class.day == target_day_code:
            if not any(item['student'].id == student.id and item['subject'] == 'SYNTAX' for item in class_list):
                item = item_base.copy()
                item.update({'subject': 'SYNTAX', 'class_time': student.syntax_class, 'start_time': student.syntax_class.start_time})
                class_list.append(item)
        
        if student.reading_class and student.reading_class.day == target_day_code:
            if not any(item['student'].id == student.id and item['subject'] == 'READING' for item in class_list):
                item = item_base.copy()
                item.update({'subject': 'READING', 'class_time': student.reading_class, 'start_time': student.reading_class.start_time})
                class_list.append(item)
        
        if student.extra_class and student.extra_class.day == target_day_code:
            item = item_base.copy()
            item.update({
                'subject': f"{student.get_extra_class_type_display()} (추가)",
                'class_time': student.extra_class,
                'start_time': student.extra_class.start_time,
                'is_extra': True,
            })
            class_list.append(item)

    class_list.sort(key=lambda x: x['start_time'] if x['start_time'] else time(23, 59))

    return render(request, 'academy/class_management.html', {
        'target_date': target_date, 
        'class_list': class_list,
        'search_query': search_query
    })


# ==============================================================================
# 원장님용 대시보드 (수정됨)
# ==============================================================================
@user_passes_test(lambda u: u.is_superuser)
def director_dashboard(request):
    date_str = request.GET.get('date')
    if date_str:
        try: today = datetime.strptime(date_str, '%Y-%m-%d').date()
        except ValueError: today = timezone.now().date()
    else:
        today = timezone.now().date()

    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    today_day_code = weekday_map[today.weekday()]
    
    # [수정 1] "27점 이상(통과)"인 시험 중 가장 최근 날짜 조회
    students = StudentProfile.objects.filter(
        Q(syntax_class__day=today_day_code) | 
        Q(reading_class__day=today_day_code) |
        Q(extra_class__day=today_day_code) |
        Q(temp_schedules__new_date=today)
    ).distinct().annotate(
        last_passed_at=Max('test_results__created_at', filter=Q(test_results__score__gte=27))
    )
    
    dashboard_data = []
    now = timezone.now()
    
    for student in students:
        attendance = Attendance.objects.filter(student=student, date=today).first()
        if attendance:
            status_code = attendance.status
        else:
            start_time = get_today_class_start_time(student)
            if start_time and timezone.now().time() > start_time:
                status_code = 'NONE'
            else:
                status_code = 'PENDING'

        def check_log(subj_type):
            return ClassLog.objects.filter(student=student, subject=subj_type, date=today).exists()

        # [NEW] 단어 시험 상태 계산 (통과일 기준)
        vocab_days = 0
        vocab_status = 'NONE' # 기본값
        
        if student.last_passed_at:
            diff = now - student.last_passed_at
            vocab_days = diff.days
            
            if vocab_days >= 6: vocab_status = 'DANGER'
            elif vocab_days >= 4: vocab_status = 'WARNING'
            elif vocab_days >= 2: vocab_status = 'CAUTION'
            else: vocab_status = 'GOOD'
        else:
            # 한번도 통과 기록이 없는 경우 (신규생 등)
            # 여기선 NONE 처리하지만, 필요하면 DANGER로 처리 가능
            vocab_status = 'NONE'

        # 공통 데이터 딕셔너리에 추가할 함수
        def add_data(subj_name, class_time, teacher_profile, is_temp=False):
            t_name = teacher_profile.name if teacher_profile else "미지정"
            dashboard_data.append({
                'student': student,
                'subject': subj_name,
                'time': class_time,
                'start_time_raw': class_time.start_time if class_time else None, # 정렬용
                'teacher_name': t_name,
                'attendance_status': status_code,
                'log_status': check_log(student.extra_class_type if '추가' in subj_name and not is_temp else ('SYNTAX' if '구문' in subj_name else 'READING')),
                'vocab_days': vocab_days,   # [추가]
                'vocab_status': vocab_status # [추가]
            })

        # [A] 보강 스케줄
        today_temps = TemporarySchedule.objects.filter(student=student, new_date=today)
        for ts in today_temps:
            t_user = None
            if ts.subject == 'SYNTAX': t_user = student.syntax_teacher
            elif ts.subject == 'READING': t_user = student.reading_teacher
            
            t_profile = t_user.staff_profile if t_user and hasattr(t_user, 'staff_profile') else None
            subj_display = f"{ts.get_subject_display()} (보강)"
            
            # 보강은 check_log 로직을 조금 수동으로
            l_status = check_log(ts.subject)
            t_name = t_profile.name if t_profile else "미지정"
            
            dashboard_data.append({
                'student': student,
                'subject': subj_display,
                'time': ts.target_class,
                'start_time_raw': ts.new_start_time,
                'teacher_name': t_name,
                'attendance_status': status_code,
                'log_status': l_status,
                'vocab_days': vocab_days,
                'vocab_status': vocab_status
            })

        # [B] 정규 수업
        if student.syntax_class and student.syntax_class.day == today_day_code:
            is_moved = TemporarySchedule.objects.filter(
                student=student, original_date=today, subject='SYNTAX', is_extra_class=False
            ).exists()
            if not is_moved:
                t_prof = student.syntax_teacher.staff_profile if student.syntax_teacher and hasattr(student.syntax_teacher, 'staff_profile') else None
                dashboard_data.append({
                    'student': student, 'subject': '구문', 'time': student.syntax_class, 
                    'start_time_raw': student.syntax_class.start_time,
                    'teacher_name': t_prof.name if t_prof else "미지정", 
                    'attendance_status': status_code, 
                    'log_status': check_log('SYNTAX'),
                    'vocab_days': vocab_days,
                    'vocab_status': vocab_status
                })

        if student.reading_class and student.reading_class.day == today_day_code:
            is_moved = TemporarySchedule.objects.filter(
                student=student, original_date=today, subject='READING', is_extra_class=False
            ).exists()
            if not is_moved:
                t_prof = student.reading_teacher.staff_profile if student.reading_teacher and hasattr(student.reading_teacher, 'staff_profile') else None
                dashboard_data.append({
                    'student': student, 'subject': '독해', 'time': student.reading_class, 
                    'start_time_raw': student.reading_class.start_time,
                    'teacher_name': t_prof.name if t_prof else "미지정", 
                    'attendance_status': status_code, 
                    'log_status': check_log('READING'),
                    'vocab_days': vocab_days,
                    'vocab_status': vocab_status
                })

        if student.extra_class and student.extra_class.day == today_day_code:
            t_prof = student.extra_class_teacher.staff_profile if student.extra_class_teacher and hasattr(student.extra_class_teacher, 'staff_profile') else None
            dashboard_data.append({
                'student': student, 
                'subject': f"{student.get_extra_class_type_display()} (추가)", 
                'time': student.extra_class, 
                'start_time_raw': student.extra_class.start_time,
                'teacher_name': t_prof.name if t_prof else "미지정", 
                'attendance_status': status_code, 
                'log_status': check_log(student.extra_class_type),
                'vocab_days': vocab_days,
                'vocab_status': vocab_status
            })

    # 기본 정렬: 시간순
    dashboard_data.sort(key=lambda x: x['start_time_raw'] if x['start_time_raw'] else time(23, 59))
    
    return render(request, 'academy/director_dashboard.html', {'dashboard_data': dashboard_data, 'today': today})


@login_required
def vice_dashboard(request):
    """부원장님용 대시보드 (수정됨)"""
    if not hasattr(request.user, 'staff_profile') or request.user.staff_profile.position != 'VICE':
        messages.error(request, "부원장 권한이 필요합니다.")
        return redirect('core:teacher_home')

    date_str = request.GET.get('date')
    target_date = datetime.strptime(date_str, '%Y-%m-%d').date() if date_str else timezone.now().date()
    my_teachers = request.user.staff_profile.managed_teachers.all()
    
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    target_day_code = weekday_map[target_date.weekday()]
    
    # [수정] 통과일 기준 Max 조회
    students = StudentProfile.objects.filter(
        Q(syntax_teacher__in=my_teachers, syntax_class__day=target_day_code) |
        Q(reading_teacher__in=my_teachers, reading_class__day=target_day_code) |
        Q(extra_class_teacher__in=my_teachers, extra_class__day=target_day_code)
    ).distinct().annotate(
        last_passed_at=Max('test_results__created_at', filter=Q(test_results__score__gte=27))
    )

    dashboard_data = []
    now = timezone.now()

    for student in students:
        attendance = Attendance.objects.filter(student=student, date=target_date).first()
        status_code = attendance.status if attendance else ('NONE' if target_date == timezone.now().date() and get_today_class_start_time(student) and timezone.now().time() > get_today_class_start_time(student) else 'PENDING')

        def check_log(subj_type, teacher_list):
            return ClassLog.objects.filter(student=student, subject=subj_type, date=target_date, teacher__in=teacher_list).exists()
            
        # [NEW] 단어 상태 계산
        vocab_days = 0
        vocab_status = 'NONE'
        
        if student.last_passed_at:
            diff = now - student.last_passed_at
            vocab_days = diff.days
            if vocab_days >= 6: vocab_status = 'DANGER'
            elif vocab_days >= 4: vocab_status = 'WARNING'
            elif vocab_days >= 2: vocab_status = 'CAUTION'
            else: vocab_status = 'GOOD'
        else:
            vocab_status = 'NONE'

        if student.syntax_teacher in my_teachers and student.syntax_class and student.syntax_class.day == target_day_code:
             dashboard_data.append({
                 'student': student, 'subject': '구문', 'time': student.syntax_class, 
                 'teacher': student.syntax_teacher, 
                 'log_status': check_log('SYNTAX', my_teachers), 
                 'attendance_status': status_code,
                 'vocab_days': vocab_days,
                 'vocab_status': vocab_status
             })

        if student.reading_teacher in my_teachers and student.reading_class and student.reading_class.day == target_day_code:
             dashboard_data.append({
                 'student': student, 'subject': '독해', 'time': student.reading_class, 
                 'teacher': student.reading_teacher, 
                 'log_status': check_log('READING', my_teachers), 
                 'attendance_status': status_code,
                 'vocab_days': vocab_days,
                 'vocab_status': vocab_status
             })
            
        if student.extra_class_teacher in my_teachers and student.extra_class and student.extra_class.day == target_day_code:
             dashboard_data.append({
                 'student': student, 'subject': f"{student.get_extra_class_type_display()} (추가)", 
                 'time': student.extra_class, 'teacher': student.extra_class_teacher, 
                 'log_status': check_log(student.extra_class_type, my_teachers), 
                 'attendance_status': status_code,
                 'vocab_days': vocab_days,
                 'vocab_status': vocab_status
             })

    dashboard_data.sort(key=lambda x: x['time'].start_time if x['time'] else time(23, 59))
    return render(request, 'academy/vice_dashboard.html', {'target_date': target_date, 'dashboard_data': dashboard_data, 'my_teachers': my_teachers})

@login_required
def student_history(request, student_id):
    """학생 상세 이력"""
    student = get_object_or_404(StudentProfile, id=student_id)
    logs = ClassLog.objects.filter(student=student).select_related('teacher', 'hw_vocab_book', 'hw_main_book').order_by('-date')
    attendances = Attendance.objects.filter(student=student).order_by('-date')

    # [NEW] 상세 페이지도 통과일 기준으로 수정
    last_passed = student.test_results.filter(score__gte=27).order_by('-created_at').first()
    
    vocab_days = None
    if last_passed:
        diff = timezone.now() - last_passed.created_at
        vocab_days = diff.days

    context = {
        'student': student,
        'logs': logs,
        'attendances': attendances,
        'vocab_days': vocab_days, 
    }
    return render(request, 'academy/student_history.html', context)