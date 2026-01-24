from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import permissions, status
from django.utils import timezone
from datetime import datetime
from django.db.models import Q
from django.contrib.auth import get_user_model

# Models
from core.models import StudentProfile, StaffProfile
from academy.models import Attendance, ClassLog, TemporarySchedule

User = get_user_model()

class DailyStudentStatusView(APIView):
    """
    [담당 강사 관리] 일일 학생 현황 (출결/일지/보강)
    - 원장: 지점 전체
    - 부원장: 담당 강사(managed_teachers) + 본인 반
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        user = request.user
        
        # 1. 권한 체크 및 날짜 파싱
        date_str = request.query_params.get('date')
        if date_str:
            try:
                target_date = datetime.strptime(date_str, '%Y-%m-%d').date()
            except ValueError:
                return Response({'error': 'Invalid date format'}, status=status.HTTP_400_BAD_REQUEST)
        else:
            target_date = timezone.now().date()

        if not hasattr(user, 'staff_profile'):
            return Response({'error': 'Permission denied (Not staff)'}, status=status.HTTP_403_FORBIDDEN)
        
        staff_profile = user.staff_profile
        branch_id = request.query_params.get('branch_id') # 원장님 필터용

        # 2. 대상 강사 선정 (Target Teachers)
        target_teachers = []
        is_principal = staff_profile.position == 'PRINCIPAL' or user.is_superuser
        
        if is_principal:
            # 원장: 해당 지점의 모든 강사 (또는 파라미터로 받은 지점)
            target_branch = branch_id if branch_id else staff_profile.branch_id
            if target_branch:
                target_teachers = User.objects.filter(staff_profile__branch_id=target_branch, is_staff=True)
            else:
                target_teachers = User.objects.filter(is_staff=True) # 전체
        else:
            # 부원장/일반강사: managed_teachers + 본인
            managed_ids = list(staff_profile.managed_teachers.values_list('id', flat=True))
            managed_ids.append(user.id)
            target_teachers = User.objects.filter(id__in=managed_ids)

        if not target_teachers.exists():
             return Response({'date': target_date, 'students': []})

        # 3. 대상 학생 선정 (Managed Students)
        # 해당 강사들이 담당하는 모든 학생 (일단 범위 넓게 잡고 날짜로 필터링)
        # is_active=True 체크 (퇴원생 제외)
        students = StudentProfile.objects.filter(
            Q(syntax_teacher__in=target_teachers) |
            Q(reading_teacher__in=target_teachers) |
            Q(extra_class_teacher__in=target_teachers)
        ).filter(user__is_active=True).distinct().select_related('syntax_teacher', 'reading_teacher', 'school')

        # 4. 오늘 등원해야 하는 학생 필터링
        weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
        today_key = weekdays[target_date.weekday()]
        
        results = []
        
        # Bulk Fetching Optimization? 
        # Loop이 많지 않으므로 일단 직관적으로 구현.
        
        for student in students:
            should_attend = False
            makeup_info = None
            absent_info = None # 결석 예정 정보 (보강 미정 등)
            
            # (1) 정규 수업 확인
            has_regular = False
            if student.syntax_class and student.syntax_class.day == today_key: has_regular = True
            if student.reading_class and student.reading_class.day == today_key: has_regular = True
            # extra_class logic (if daily) - usually extra class is fixed date or weekly? Assuming weekly for simplicity if it has 'day'
            if student.extra_class and student.extra_class.day == today_key: has_regular = True
            
            # (2) 임시 스케줄 확인 (보강/결석)
            # 오늘 날짜에 대한 변경 사항 조회
            # - new_date == today: 오늘로 보강 옴 (등원 O)
            # - original_date == today: 오늘 수업 빠짐 (등원 X, but 리스트엔 나와야 함)
            
            temp_schedules = TemporarySchedule.objects.filter(student=student)
            
            # A. 오늘로 보강 잡힌 건 (Add)
            makeup_today = temp_schedules.filter(new_date=target_date).exists()
            
            # B. 오늘 원래 수업인데 빠지는 건 (Cancel/Reschedule)
            # is_extra_class=False인 경우만 정규 수업 취소로 간주? (모델 확인 필요하지만 보통 cancel은 new_date=null or other)
            # original_date가 오늘인 스케줄 찾기
            cancelled_today_qs = temp_schedules.filter(original_date=target_date)
            is_cancelled = cancelled_today_qs.exists()
            
            if makeup_today:
                should_attend = True
            elif has_regular:
                if is_cancelled:
                    should_attend = False 
                    # 원래 와야 하는데 안 오는 경우 -> 리스트에는 포함하되 '보강 여부' 표시
                    # 보강이 잡혔는지 확인: cancelled_item.new_date is not None
                    makeup_sched = cancelled_today_qs.first()
                    if makeup_sched and makeup_sched.new_date:
                        absent_info = f"보강: {makeup_sched.new_date}"
                    else:
                        absent_info = "보강 미정"
                else:
                    should_attend = True
            
            # (3) 리스트 포함 여부 결정
            # - 등원 예정이거나 (should_attend)
            # - 원래 등원일인데 결석인 경우 (has_regular and is_cancelled) -> 관리 대상임
            
            is_target = should_attend or (has_regular and is_cancelled)
            
            if is_target:
                # 5. 상태 조회
                attendance = None
                if should_attend:
                    att_obj = Attendance.objects.filter(student=student, date=target_date).first()
                    attendance = att_obj.status if att_obj else 'NONE' # 미등원
                else:
                    attendance = 'ABSENT_PLANNED' # 예정된 결석 (보강 등)
                
                # 일지 작성 여부
                # [TODO] 과목별로 체크해야 하나? 하나라도 있으면 OK? -> 일단 하나라도 있으면 OK
                # 상세는 눌러서 확인
                has_log = ClassLog.objects.filter(student=student, date=target_date).exists()
                
                # 담당 선생님 이름 (대표 1명)
                teacher_name = "-"
                if student.syntax_teacher: teacher_name = student.syntax_teacher.staff_profile.name
                elif student.reading_teacher: teacher_name = student.reading_teacher.staff_profile.name
                
                results.append({
                    'id': student.id,
                    'name': student.name,
                    'school': student.school.name if student.school else "-",
                    'grade': student.current_grade_display,
                    'teacher': teacher_name,
                    'attendance': attendance, # PRESENT, LATE, ABSENT, NONE, ABSENT_PLANNED
                    'has_log': has_log,
                    'absent_info': absent_info, # 보강 정보 (결석인 경우)
                    'is_cancelled': is_cancelled and not makeup_today
                })

        # 6. 정렬 (등원 예정이 위로, 그 다음 결석)
        results.sort(key=lambda x: (x['is_cancelled'], x['name']))
        
        # 7. 통계
        total_count = len(results)
        present_count = len([r for r in results if r['attendance'] in ['PRESENT', 'LATE']])
        log_count = len([r for r in results if r['has_log']])
        
        return Response({
            'date': target_date,
            'summary': {
                'total': total_count,
                'present': present_count,
                'log_completed': log_count
            },
            'students': results
        })
