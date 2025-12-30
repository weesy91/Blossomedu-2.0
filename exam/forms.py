from django import forms
from django.contrib.auth import get_user_model
from django.db.models import Q  # 👈 [추가] 이게 빠져서 에러가 났습니다!
from core.models import StudentProfile
from academy.models import Textbook
from .models import TestPaper

User = get_user_model()

class TestPaperGenerationForm(forms.ModelForm):
    # 1. 담당 선생님
    teacher = forms.ModelChoiceField(
        queryset=User.objects.none(),
        label="담당 선생님",
        widget=forms.Select(attrs={'class': 'form-select', 'id': 'teacher-select'})
    )

    # 2. 응시 학생
    student = forms.ModelChoiceField(
        queryset=StudentProfile.objects.none(),
        label="응시 학생",
        widget=forms.Select(attrs={'class': 'form-select', 'id': 'student-select'})
    )

    # 3. 교재
    textbook = forms.ModelChoiceField(
        queryset=Textbook.objects.all(),
        label="출제 교재",
        widget=forms.Select(attrs={'class': 'form-select'})
    )

    # 4. 범위
    start_chapter = forms.IntegerField(
        label="시작 강", 
        widget=forms.NumberInput(attrs={'class': 'form-control', 'placeholder': '1'})
    )
    end_chapter = forms.IntegerField(
        label="끝 강", 
        widget=forms.NumberInput(attrs={'class': 'form-control', 'placeholder': '5'})
    )

    # 5. 비율 슬라이더
    concept_ratio = forms.IntegerField(
        label="개념 문제 비율 (%)",
        initial=50,
        widget=forms.NumberInput(attrs={
            'class': 'form-range', 
            'type': 'range', 
            'min': '0', 'max': '100', 'step': '10',
            'oninput': "document.getElementById('ratioVal').innerText = this.value + '%'"
        })
    )
    
    # 6. 총 문제 수
    total_questions = forms.IntegerField(
        label="총 문제 수", 
        initial=20,
        widget=forms.NumberInput(attrs={'class': 'form-control', 'min': '1'})
    )

    # 7. 제목 (custom_title 사용)
    custom_title = forms.CharField(
        label="시험지 제목 (선택)", 
        required=False, 
        widget=forms.TextInput(attrs={'class': 'form-control', 'placeholder': '비워두면 자동 생성'})
    )

    class Meta:
        model = TestPaper
        # title 제거 -> 뷰에서 처리
        fields = ['student'] 

    def __init__(self, *args, **kwargs):
        user = kwargs.pop('user', None)
        super().__init__(*args, **kwargs)

        # === 1. 선생님 목록 채우기 ===
        if user:
            if user.is_superuser:
                self.fields['teacher'].queryset = User.objects.filter(is_staff=True).order_by('username')
            elif hasattr(user, 'staff_profile') and user.staff_profile.position == 'VICE':
                managed = list(user.staff_profile.managed_teachers.all())
                team = [user.id] + [t.id for t in managed]
                self.fields['teacher'].queryset = User.objects.filter(id__in=team).order_by('username')
            else:
                self.fields['teacher'].queryset = User.objects.filter(id=user.id)
                self.fields['teacher'].initial = user

        # === 2. POST 요청(저장 시) 학생 목록 유효성 검사 통과시키기 ===
        if self.data.get('teacher'):
            try:
                teacher_id = int(self.data.get('teacher'))
                self.fields['student'].queryset = StudentProfile.objects.filter(
                    # 👇 [수정] models.Q -> Q 로 변경 (import 했으므로)
                    Q(syntax_teacher_id=teacher_id) | 
                    Q(reading_teacher_id=teacher_id) | 
                    Q(extra_class_teacher_id=teacher_id)
                ).distinct()
            except (ValueError, TypeError):
                self.fields['student'].queryset = StudentProfile.objects.none()
        
        # GET 요청(처음 화면 뜰 때) 로직 - 일반 선생님 편의성
        elif user and not user.is_superuser and not (hasattr(user, 'staff_profile') and user.staff_profile.position == 'VICE'):
             self.fields['student'].queryset = StudentProfile.objects.filter(
                Q(syntax_teacher=user) | 
                Q(reading_teacher=user) | 
                Q(extra_class_teacher=user)
             ).distinct()