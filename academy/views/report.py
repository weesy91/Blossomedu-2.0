from rest_framework import viewsets, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.utils import timezone
import traceback
import json

# Import Models centrally or locally to avoid circular imports if necessary
from academy.models import StudentReport, Attendance, ClassLog, AssignmentTask
from academy.serializers import StudentReportSerializer

class StudentReportViewSet(viewsets.ModelViewSet):
    queryset = StudentReport.objects.all()
    serializer_class = StudentReportSerializer
    permission_classes = [permissions.IsAuthenticated]

    def get_queryset(self):
        try:
            user = self.request.user
            if hasattr(user, 'profile'):
                return StudentReport.objects.filter(student=user.profile).order_by('-created_at')
            if user.is_staff:
                return StudentReport.objects.all().order_by('-created_at')
        except Exception:
            pass
        return StudentReport.objects.none()

    @action(detail=False, methods=['post'])
    def generate(self, request):
        """
        성적표 생성 (데이터 집계 및 스냅샷 저장)
        SAFE MODE: 모든 에러를 200 OK JSON으로 반환
        """
        try:
            student_id = request.data.get('student_id')
            start_date_str = request.data.get('start_date')
            end_date_str = request.data.get('end_date')
            title = request.data.get('title', '학습 리포트')
            comment = request.data.get('teacher_comment', '')

            if not all([student_id, start_date_str, end_date_str]):
                return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

            # 1. 데이터 집계
            snapshot = self._aggregate_data(student_id, start_date_str, end_date_str)

            # 2. 리포트 생성
            # date validation is handled by DB or models
            report = StudentReport.objects.create(
                student_id=student_id,
                teacher=request.user,
                title=title,
                start_date=start_date_str,
                end_date=end_date_str,
                data_snapshot=snapshot,
                teacher_comment=comment
            )

            return Response(self.get_serializer(report).data)

        except Exception as e:
            # Catch-all Exception Handler to prevent 500 HTML
            return Response({
                'error': str(e),
                'trace': traceback.format_exc(),
                'status': 'error',
                'message': '서버 내부 오류가 발생했습니다. 개발자에게 문의해주세요.'
            }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['post'])
    def preview(self, request):
        try:
            student_id = request.data.get('student_id')
            start_date_str = request.data.get('start_date')
            end_date_str = request.data.get('end_date')

            if not all([student_id, start_date_str, end_date_str]):
                return Response({'error': 'Missing required fields'}, status=status.HTTP_400_BAD_REQUEST)

            snapshot = self._aggregate_data(student_id, start_date_str, end_date_str)
            return Response(snapshot)
        except Exception as e:
            return Response({
                'error': str(e),
                'trace': traceback.format_exc(),
                'status': 'error'
            }, status=status.HTTP_200_OK)

    @action(detail=False, methods=['get'], permission_classes=[permissions.AllowAny], url_path='public/(?P<uuid>[^/.]+)')
    def public_view(self, request, uuid=None):
        try:
            report = StudentReport.objects.get(uuid=uuid)
            return Response(self.get_serializer(report).data)
        except StudentReport.DoesNotExist:
            return Response({'error': 'Not found'}, status=status.HTTP_404_NOT_FOUND)
        except Exception as e:
            return Response({'error': str(e)}, status=status.HTTP_200_OK)

    def _aggregate_data(self, student_id, start, end):
        # (1) Attendance
        attendances = []
        try:
            attendances = list(Attendance.objects.filter(
                student_id=student_id, 
                date__range=[start, end]
            ).values('date', 'status', 'check_in_time'))
        except Exception:
            attendances = []

        # (2) Vocab
        vocab_tests = []
        cumulative_passed = 0
        try:
            from vocab.models import TestResult
            vocab_qs = TestResult.objects.filter(
                student_id=student_id,
                created_at__date__range=[start, end]
            ).select_related('book').prefetch_related('details').order_by('created_at')
            
            for v in vocab_qs:
                try:
                    wrong_words = []
                    for d in v.details.all():
                        if not d.is_correct:
                            wrong_words.append({
                                'word': d.word_question,
                                'student': d.student_answer,
                                'answer': d.correct_answer
                            })
                    cumulative_passed += v.score
                    vocab_tests.append({
                        'created_at': v.created_at,
                        'score': v.score,
                        'total_count': v.total_count,
                        'wrong_count': v.wrong_count,
                        'book__title': v.book.title,
                        'test_range': v.test_range,
                        'wrong_words': wrong_words,
                        'cumulative_passed': cumulative_passed, 
                    })
                except Exception:
                    continue
        except Exception:
            pass

        # (3) Assignments
        assignments = []
        try:
            from django.core.exceptions import ObjectDoesNotExist
            assignments_qs = AssignmentTask.objects.filter(
                student_id=student_id,
                due_date__date__range=[start, end]
            ).select_related('related_textbook', 'related_vocab_book').prefetch_related('submission').order_by('due_date')
            
            for a in assignments_qs:
                try:
                    feedback = ''
                    status = '미제출'
                    submission_image = None
                    
                    try:
                        submission = a.submission
                        feedback = submission.teacher_comment
                        status = submission.get_status_display()
                        if submission.image and submission.image.name:
                            try: submission_image = submission.image.url
                            except: pass
                    except ObjectDoesNotExist:
                        if a.is_completed:
                            status = '완료'
                    
                    assignments.append({
                        'title': a.title,
                        'due_date': a.due_date,
                        'is_completed': a.is_completed,
                        'assignment_type': a.get_assignment_type_display(),
                        'status': status,
                        'feedback': feedback,
                        'submission_image': submission_image,
                    })
                except Exception:
                    continue
        except Exception:
            pass

        # (4) Logs
        logs = []
        try:
            logs_qs = ClassLog.objects.filter(
                student_id=student_id,
                date__range=[start, end]
            ).prefetch_related('entries', 'entries__textbook', 'entries__wordbook', 'generated_assignments').order_by('-date')
            
            for l in logs_qs:
                try:
                    details = []
                    for e in l.entries.all():
                        book_name = e.textbook.title if e.textbook else (e.wordbook.title if e.wordbook else '기타')
                        details.append({
                            'text': f"{book_name} ({e.progress_range})",
                            'score': e.score or '-',
                        })
                    
                    homeworks = []
                    # generated_assignments is standard related_name? Check models.
                    # academy/models.py: ClassLog -> related_name='generated_assignments'
                    for t in l.generated_assignments.all():
                        homeworks.append({
                            'title': t.title,
                            'due_date': t.due_date,
                            'is_completed': t.is_completed,
                        })
                    
                    logs.append({
                        'date': l.date,
                        'subject': l.get_subject_display(),
                        'subject_code': l.subject, 
                        'comment': l.comment,
                        'teacher_comment': l.teacher_comment,
                        'details': details,
                        'homeworks': homeworks,
                    })
                except Exception as e:
                    # Specific log entry fail
                    continue
        except Exception:
            pass

        # Stats
        try:
            total_days = len(attendances)
            present_days = sum(1 for a in attendances if a['status'] == 'PRESENT')
            vocab_avg = 0
            if vocab_tests:
                vocab_avg = sum(t['score'] for t in vocab_tests) / len(vocab_tests)
        except Exception:
            total_days = 0
            present_days = 0
            vocab_avg = 0

        # Safe Serializer
        def recursive_serialize(data):
            try:
                if data is None: 
                    return None
                if isinstance(data, (bool, int, float, str)):
                    return data
                if isinstance(data, dict):
                    return {k: recursive_serialize(v) for k, v in data.items()}
                elif isinstance(data, list):
                    return [recursive_serialize(item) for item in data]
                elif hasattr(data, 'isoformat'):
                    return data.isoformat()
                elif hasattr(data, 'url'): 
                    try: return data.url
                    except: return None
                # FORCE STRING
                return str(data)
            except:
                return str(data)

        return {
            'stats': {
                'attendance_rate': (present_days / total_days * 100) if total_days > 0 else 0,
                'vocab_avg': round(vocab_avg, 1),
                'assignment_count': len(assignments),
                'assignment_completed': sum(1 for a in assignments if a['is_completed']),
                'total_passed_words': cumulative_passed, 
            },
            'attendance': recursive_serialize(list(attendances)),
            'vocab': recursive_serialize(vocab_tests),
            'assignments': recursive_serialize(assignments),
            'logs': recursive_serialize(logs),
        }
