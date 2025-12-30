from django.shortcuts import render, redirect
from django.urls import reverse
from django.contrib.auth import login, logout
from django.contrib.auth.forms import AuthenticationForm
from django.contrib.auth.decorators import login_required # [중요] 이 줄이 활성화되어야 합니다!

def login_view(request):
    """로그인 페이지 처리"""
    if request.user.is_authenticated:
        # 이미 로그인 상태라면 권한에 맞게 리다이렉트
        if request.user.is_staff or request.user.is_superuser:
            return redirect('core:teacher_home')
        return redirect('vocab:index')

    if request.method == 'POST':
        form = AuthenticationForm(request, data=request.POST)
        if form.is_valid():
            user = form.get_user()
            login(request, user)
            
            # 로그인 성공 후 계정 타입에 따라 이동 경로 분기
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
    """메인 대시보드 (로그인한 사람만 볼 수 있음)"""
    return render(request, 'core/index.html', {
        'user': request.user
    })

def login_dispatch(request):
    # 👇 [추가] 터미널에 이 로그가 찍히는지 확인해주세요!
    print(f"로그인 감지! 사용자: {request.user}, 슈퍼유저여부: {request.user.is_superuser}")

    if request.user.is_superuser:
        print(">>> 관리자 페이지로 이동합니다.")  # 확인용
        return redirect('admin:index')
    
    if hasattr(request.user, 'staff_profile'):
        print(">>> 선생님 페이지로 이동합니다.")  # 확인용
        return redirect('core:teacher_home')
        
    return redirect('core:teacher_home')

@login_required(login_url='core:login')
def teacher_home(request):
    """선생님 메인 허브"""
    # 선생님이 아니면 접근 불가
    if not request.user.is_staff:
        return redirect('vocab:index')
    return render(request, 'core/teacher_home.html')