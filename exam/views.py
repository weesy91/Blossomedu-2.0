from django.shortcuts import render, redirect, get_object_or_404
from django.contrib.auth.decorators import login_required, user_passes_test
from django.contrib import messages
from django.core.files.base import ContentFile
from django.http import JsonResponse 
from django.db.models import Q
from pdf2image import convert_from_bytes
import random
import re
import io
import platform
from PIL import Image, ImageChops 

from .models import Question, TestPaper
from .forms import TestPaperGenerationForm
from academy.models import Textbook
from core.models import StudentProfile 

# Poppler 경로 (윈도우면 경로 확인 필요)
if platform.system() == 'Windows':
    POPPLER_PATH = r"C:\Program Files\poppler-24.08.0\Library\bin"
else:
    POPPLER_PATH = None 

# [보조 함수] 이미지 여백 제거
def trim_whitespace(im):
    bg = Image.new(im.mode, im.size, im.getpixel((0,0)))
    diff = ImageChops.difference(im, bg)
    diff = ImageChops.add(diff, diff, 2.0, -100)
    bbox = diff.getbbox()
    if bbox:
        return im.crop(bbox)
    return im

# 1. 이미지/PDF 업로드 뷰
@user_passes_test(lambda u: u.is_superuser)
def upload_images_bulk(request):
    academy_books = Textbook.objects.all().order_by('category', 'title')

    if request.method == 'POST':
        files = request.FILES.getlist('images')
        book_name = request.POST.get('book_name')
        default_style = request.POST.get('style') 
        reading_type_input = request.POST.get('reading_type', 'NONE')
        
        category = 'SYNTAX'
        try:
            selected_book = Textbook.objects.get(title=book_name)
            category = selected_book.category
        except Textbook.DoesNotExist:
            pass

        if not files:
            messages.error(request, "파일을 선택해주세요.")
            return redirect('exam:upload_images')

        success_count = 0
        Image.MAX_IMAGE_PIXELS = None 

        for f in files:
            numbers = re.findall(r'\d+', f.name)
            if not numbers: continue
            chapter = int(numbers[0])
            filename = f.name.lower()
            
            # 기본 설정
            current_style = default_style
            start_offset = 0  
            
            # [구문/어법 교재] 파일명 자동 분류
            if '구문' in filename or '분석' in filename or 'syntax' in filename:
                current_style = 'ANALYSIS'
                start_offset = 500         
            elif '개념' in filename or 'concept' in filename:
                current_style = 'CONCEPT'
                start_offset = 0      

            # [독해 교재] 유형에 따른 스타일 분기 (핵심 로직)
            current_reading_type = 'NONE'
            if category == 'READING':
                current_reading_type = reading_type_input 
                
                if current_reading_type == 'STRUCT':
                    # Type S(구조분석) -> 구문 스타일(500번대)로 저장
                    current_style = 'ANALYSIS'
                    start_offset = 500
                else:
                    # Type A~D(일반지문) -> 개념 스타일(1번대)로 저장
                    current_style = 'CONCEPT'
                    start_offset = 0

            is_answer = ('답' in filename or 'sol' in filename)

            if filename.endswith('.pdf'):
                try:
                    pages = convert_from_bytes(f.read(), poppler_path=POPPLER_PATH, dpi=200, strict=False, use_cropbox=True)
                    for i, page in enumerate(pages):
                        try:
                            question_number = (i + 1) + start_offset
                            page = page.convert('RGB')
                            page = trim_whitespace(page) # 여백 제거
                            
                            img_byte_arr = io.BytesIO()
                            page.save(img_byte_arr, format='JPEG', quality=90)
                            
                            file_name_str = f"{chapter}_{question_number}_{current_style}.jpg"
                            content_file = ContentFile(img_byte_arr.getvalue(), name=file_name_str)
                            
                            if is_answer:
                                try:
                                    q = Question.objects.get(book_name=book_name, chapter=chapter, number=question_number)
                                    q.answer_image = content_file
                                    q.save()
                                except Question.DoesNotExist: pass
                            else:
                                Question.objects.update_or_create(
                                    book_name=book_name, chapter=chapter, number=question_number,
                                    defaults={
                                        'category': category, 
                                        'style': current_style,
                                        'reading_type': current_reading_type,
                                        'question_text': f"(PDF {chapter}강-{question_number})",
                                        'image': content_file
                                    }
                                )
                                success_count += 1
                        except Exception as inner_e: print(f"Page Error: {inner_e}")
                except Exception as e: messages.error(request, f"PDF Error: {e}")
            else:
                # 이미지 파일 처리
                if len(numbers) >= 2:
                    raw_num = int(numbers[1])
                    # 독해는 start_offset을 따름 (Type S면 500 더해짐)
                    if category == 'READING':
                        q_num = raw_num + start_offset
                    else:
                        q_num = raw_num + 500 if (current_style == 'ANALYSIS' and raw_num < 500) else raw_num
                    
                    if is_answer:
                        try:
                            q = Question.objects.get(book_name=book_name, chapter=chapter, number=q_num)
                            q.answer_image = f
                            q.save()
                        except: pass
                    else:
                        Question.objects.update_or_create(
                            book_name=book_name, chapter=chapter, number=q_num,
                            defaults={
                                'category': category, 
                                'style': current_style, 
                                'reading_type': current_reading_type,
                                'image': f
                            }
                        )
                        success_count += 1

        messages.success(request, f"✅ 총 {success_count}개 문항 저장 완료!")
        return redirect('exam:upload_images')
    
    return render(request, 'exam/upload_images.html', {'academy_books': academy_books})

# 2. 시험지 생성 뷰
@login_required
def create_test_paper(request):
    if request.method == 'POST':
        form = TestPaperGenerationForm(request.POST, user=request.user)
        if form.is_valid():
            data = form.cleaned_data
            all_questions = Question.objects.filter(
                book_name=data['textbook'].title,
                chapter__gte=data['start_chapter'],
                chapter__lte=data['end_chapter']
            )
            concept_pool = list(all_questions.filter(style='CONCEPT'))
            analysis_pool = list(all_questions.filter(style='ANALYSIS'))
            
            target_concept_count = int(data['total_questions'] * (data['concept_ratio'] / 100))
            
            selected_concepts = []
            if len(concept_pool) >= target_concept_count:
                selected_concepts = random.sample(concept_pool, target_concept_count)
            else:
                selected_concepts = concept_pool
                random.shuffle(selected_concepts) 

            remaining_slots = data['total_questions'] - len(selected_concepts)
            selected_analysis = []
            if len(analysis_pool) >= remaining_slots:
                selected_analysis = random.sample(analysis_pool, remaining_slots)
            else:
                selected_analysis = analysis_pool
                random.shuffle(selected_analysis) 
            
            final_questions = selected_concepts + selected_analysis

            paper = TestPaper.objects.create(
                student=data['student'], 
                title=data['custom_title'] or f"{data['student'].name} - {data['textbook'].title}",
                target_chapters=f"{data['textbook'].title} {data['start_chapter']}~{data['end_chapter']}강"
            )
            paper.questions.set(final_questions)
            return redirect('exam:print_test_paper', paper_id=paper.id)
    else:
        form = TestPaperGenerationForm(user=request.user)
    return render(request, 'exam/create_test_paper.html', {'form': form})

# 3. 시험지 인쇄 뷰 (여기가 정렬의 핵심)
@login_required
def print_test_paper(request, paper_id):
    paper = get_object_or_404(TestPaper, id=paper_id)
    
    # [정렬 로직]
    # style이 CONCEPT(지문)이면 0, ANALYSIS(구조분석)이면 1 -> 지문이 먼저 나옴!
    sorted_questions = sorted(
        paper.questions.all(), 
        key=lambda q: (0 if q.style == 'CONCEPT' else 1, q.chapter, q.number)
    )
    
    return render(request, 'exam/print_test_paper.html', {
        'paper': paper, 
        'questions': sorted_questions 
    })

# 4. API
@login_required
def get_students_by_teacher(request):
    teacher_id = request.GET.get('teacher_id')
    if not teacher_id: return JsonResponse({'students': []})
    try:
        students = StudentProfile.objects.filter(
            Q(syntax_teacher_id=teacher_id) | Q(reading_teacher_id=teacher_id) | Q(extra_class_teacher_id=teacher_id)
        ).select_related('school').distinct().values('id', 'name', 'school__name')
        data = [{'id': s['id'], 'name': f"{s['name']} ({s['school__name'] or '학교미정'})"} for s in students]
        data.sort(key=lambda x: x['name'])
        return JsonResponse({'students': data})
    except: return JsonResponse({'students': []})