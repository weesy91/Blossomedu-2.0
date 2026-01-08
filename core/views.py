from django.shortcuts import render, redirect
from django.urls import reverse, reverse_lazy
from django.contrib.auth import login, logout
from django.contrib.auth.forms import AuthenticationForm
from django.contrib.auth.decorators import login_required
from django.contrib.auth.views import PasswordChangeView
from django.contrib import messages
from django.utils import timezone
from django.http import JsonResponse
from django.db.models import Q, Max 
import calendar 
from datetime import timedelta, time

# [모델 임포트 정리]
# core 앱의 모델들
from .models import StudentProfile, ClassTime, Popup 
# academy 앱의 모델들
from academy.models import Attendance, TemporarySchedule, ClassLog

def login_view(request):
    """로그인 페이지 처리"""
    if request.user.is_authenticated:
        if request.user.is_staff or request.user.is_superuser:
            return redirect('core:teacher_home')
        return redirect('vocab:index')

    if request.method == 'POST':
        form = AuthenticationForm(request, data=request.POST)
        if form.is_valid():
            user = form.get_user()
            login(request, user)
            return redirect('core:login_dispatch') 
    else:
        form = AuthenticationForm()
    
    return render(request, 'core/login.html', {'form': form})

def logout_view(request):
    """로그아웃 처리"""
    logout(request)
    return redirect('core:login')

@login_required(login_url='core:login')
def index(request):
    """메인 대시보드"""
    return render(request, 'core/index.html', {
        'user': request.user
    })

def login_dispatch(request):
    print(f"로그인 감지! 사용자: {request.user}, 슈퍼유저여부: {request.user.is_superuser}")
    
    # 선생님(스태프) 또는 슈퍼유저이면 선생님 홈으로
    if request.user.is_staff:
        return redirect('core:teacher_home')
        
    # 학생이면 '학생 홈'으로 이동
    return redirect('core:student_home')

@login_required(login_url='core:login')
def teacher_home(request):
    """선생님 메인 허브"""
    if not request.user.is_staff:
        return redirect('vocab:index')
    
    now = timezone.now()
    
    # [NEW] 단어 시험 오랫동안 안 본 학생 체크 (대시보드 알림용)
    # 1. 내 담당 학생 조회
    my_students = StudentProfile.objects.filter(
        Q(syntax_teacher=request.user) | Q(reading_teacher=request.user) | Q(extra_class_teacher=request.user)
    ).distinct().annotate(
        last_test_dt=Max('test_results__created_at')
    )
    
    # 2. 5일 이상 미응시자 카운트
    danger_limit = now - timedelta(days=5)
    warning_count = 0
    
    for s in my_students:
        # 시험 기록이 아예 없거나, 마지막 시험이 5일 이전인 경우
        if not s.last_test_dt or s.last_test_dt < danger_limit:
            warning_count += 1

    # 기존 월말평가 기간 계산 로직
    last_day = calendar.monthrange(now.year, now.month)[1]
    start_day = last_day - 7
    is_exam_period = (now.day >= start_day)

    context = {
        'is_exam_period': is_exam_period,
        'vocab_warning_count': warning_count, # 템플릿으로 전달
    }
    
    return render(request, 'core/teacher_home.html', context)

# 👇 [추가] 비밀번호 변경 뷰
class CustomPasswordChangeView(PasswordChangeView):
    template_name = 'core/password_change.html'
    success_url = reverse_lazy('core:student_home')
    
    def form_valid(self, form):
        messages.success(self.request, "비밀번호가 성공적으로 변경되었습니다! 🎉")
        return super().form_valid(form)
    
@login_required(login_url='core:login')
def student_home(request):
    """
    학생용 메인 대시보드
    """
    user = request.user
    today = timezone.now().date()
    
    # 1. 학생 프로필 확인 (없으면 로그인 화면으로 튕겨냄)
    if not hasattr(user, 'profile'):
        return redirect('core:login')
    
    profile = user.profile
    
    # ==========================================
    # [1] 오늘 수업 시간표 구하기 (복잡한 로직)
    # ==========================================
    weekday_map = {0: 'Mon', 1: 'Tue', 2: 'Wed', 3: 'Thu', 4: 'Fri', 5: 'Sat', 6: 'Sun'}
    today_code = weekday_map[today.weekday()]
    
    schedules = []

    # 1-1. 정규 수업 (구문/독해/추가)
    # (A) 구문 수업
    if profile.syntax_class and profile.syntax_class.day == today_code:
        is_moved = TemporarySchedule.objects.filter(
            student=profile, original_date=today, subject='SYNTAX'
        ).exists()
        if not is_moved:
            schedules.append({
                'type': '정규',
                'subject': '구문',
                'time': profile.syntax_class,
                'teacher': profile.syntax_teacher
            })

    # (B) 독해 수업
    if profile.reading_class and profile.reading_class.day == today_code:
        is_moved = TemporarySchedule.objects.filter(
            student=profile, original_date=today, subject='READING'
        ).exists()
        if not is_moved:
            schedules.append({
                'type': '정규',
                'subject': '독해',
                'time': profile.reading_class,
                'teacher': profile.reading_teacher
            })

    # (C) 추가 수업
    if profile.extra_class and profile.extra_class.day == today_code:
        # 추가 수업은 보통 이동 개념이 없으므로 그대로 표시
        label = f"{profile.get_extra_class_type_display()} (추가)"
        schedules.append({
            'type': '추가',
            'subject': label,
            'time': profile.extra_class,
            'teacher': profile.extra_class_teacher
        })

    # 1-2. 보강/일정변경 (오늘 날짜로 새로 잡힌 수업)
    temp_schedules = TemporarySchedule.objects.filter(student=profile, new_date=today)
    for ts in temp_schedules:
        # 선생님 정보 찾기
        teacher = None
        if ts.subject == 'SYNTAX': teacher = profile.syntax_teacher
        elif ts.subject == 'READING': teacher = profile.reading_teacher
        
        # 라벨 설정 (보강 vs 일정변경)
        label_type = "보강" if ts.is_extra_class else "변경됨"
        
        schedules.append({
            'type': label_type,
            'subject': ts.get_subject_display(),
            'time_obj': ts,
            'start_time': ts.new_start_time,
            'teacher': teacher
        })

    # 1-3. 시간순 정렬
    def get_start_time(item):
        if 'start_time' in item: return item['start_time']
        return item['time'].start_time
    
    schedules.sort(key=get_start_time)

    # [2] 출석 현황 (오늘)
    attendance = Attendance.objects.filter(student=profile, date=today).first()

    # [3] 최신 과제 (숙제) 가져오기
    last_log = ClassLog.objects.filter(student=profile).order_by('-date', '-created_at').first()

    # [4] 지점별 팝업 가져오기
    current_time = timezone.now()
    active_popups = Popup.objects.filter(
        Q(branch=profile.branch) | Q(branch__isnull=True),
        is_active=True,
        start_date__lte=current_time,
        end_date__gte=current_time
    )

    return render(request, 'core/student_home.html', {
        'profile': profile,
        'today': today,
        'schedules': schedules,
        'attendance': attendance,
        'last_log': last_log,
        'popups': active_popups,
    })

# 👇 [수정됨] 기존 get_classtimes_by_branch 삭제하고 이 함수로 대체!
# core/views.py

from django.http import JsonResponse
from .models import ClassTime, StudentProfile

def get_classtimes_with_availability(request):
    """
    [AJAX] 지점 시간표를 반환하되, '구문' 수업인 경우 선생님의 중복 시간을 계산하여 disabled 처리함.
    """
    branch_id = request.GET.get('branch_id')
    teacher_id = request.GET.get('teacher_id')
    role = request.GET.get('role')   # syntax, reading, extra
    extra_type = request.GET.get('type') # SYNTAX, READING (보충수업일 때만 옴)
    current_student_id = request.GET.get('student_id')

    if not branch_id:
        return JsonResponse([], safe=False)

    # 1. 해당 지점의 시간표 조회
    times = ClassTime.objects.filter(branch_id=branch_id).order_by('day', 'start_time')
    
    # 2. 마감(중복)된 시간표 ID 찾기
    occupied_ids = set()
    
    # [중복 검사 조건]
    # 선생님이 선택되어 있고, 
    # '정규 구문 수업'이거나 OR '보충 구문 수업'을 잡으려는 경우에만 검사
    should_check_overlap = False
    
    if teacher_id:
        if role == 'syntax':
            should_check_overlap = True
        elif role == 'extra' and extra_type == 'SYNTAX':
            should_check_overlap = True
            
    if should_check_overlap:
        # (A) 선생님의 '정규 구문' 학생들 시간 조회
        qs1 = StudentProfile.objects.filter(syntax_teacher_id=teacher_id)
        if current_student_id:
            qs1 = qs1.exclude(id=current_student_id)
        occupied_ids.update(list(qs1.values_list('syntax_class_id', flat=True)))

        # (B) 선생님의 '보충 구문' 학생들 시간 조회
        qs2 = StudentProfile.objects.filter(
            extra_class_teacher_id=teacher_id, 
            extra_class_type='SYNTAX'
        )
        if current_student_id:
            qs2 = qs2.exclude(id=current_student_id)
        occupied_ids.update(list(qs2.values_list('extra_class_id', flat=True)))

    # 3. 데이터 조립
    data = []
    for t in times:
        # 내가 계산한 '바쁜 시간(occupied_ids)'에 포함되면 disabled
        is_disabled = (t.id in occupied_ids)
        
        day_str = t.get_day_display()
        time_str = t.start_time.strftime('%H:%M')
        label = f"[{day_str}] {time_str} ({t.name})"
        
        if is_disabled:
            label += " ⛔(마감)"

        data.append({
            'id': t.id,
            'name': label,
            'disabled': is_disabled, 
            'raw_name': t.name 
        })
        
    return JsonResponse(data, safe=False)