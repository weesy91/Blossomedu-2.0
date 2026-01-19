import os
import sys
import django

# Add project root to sys.path
sys.path.append(os.getcwd())
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
django.setup()

from academy.models import ClassLog

print('--- Latest 10 Logs ---')
try:
    logs = ClassLog.objects.order_by('-created_at')[:10]
    print(f'Found {logs.count()} logs')
    for l in logs:
        # Check generated_assignments count
        count = l.generated_assignments.count()
        print(f'   [DB] ID: {l.id}, Date: {l.date}, Assignments: {count}')

except Exception as e:
    print(f"Error querying logs: {e}")

print('\n--- API Response Test ---')
from rest_framework.test import APIRequestFactory, force_authenticate
from academy.views_api import ClassLogViewSet
from django.contrib.auth import get_user_model

User = get_user_model()
staff = User.objects.filter(is_staff=True).first()
if staff:
    print(f'Testing with Staff User: {staff.username}')
    factory = APIRequestFactory()
    view = ClassLogViewSet.as_view({'get': 'list'})
    
    # Create request
    request = factory.get('/academy/api/v1/class-logs/', {'student_id': logs[0].student.id, 'date': logs[0].date})
    force_authenticate(request, user=staff)
    
    response = view(request)
    print(f'Status Code: {response.status_code}')
    if response.status_code == 200:
        data = response.data
        if data:
            first_log = data[0]
            print('Log Data Keys:', first_log.keys())
            files = first_log.get('generated_assignments')
            print(f"generated_assignments type: {type(files)}")
            print(f"generated_assignments content: {files}")
        else:
            print("No logs returned from API")
else:
    print("No staff user found to test API")
