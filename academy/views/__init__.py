from .attendance import attendance_kiosk
# [수정] student_history는 dashboard 유지
from .dashboard import director_dashboard, vice_dashboard, student_history

# [핵심 수정] class_management를 dashboard에서 빼고, class_log에서 가져오도록 변경
from .class_log import create_class_log, class_management

from .schedule import schedule_change, check_availability, get_occupied_times