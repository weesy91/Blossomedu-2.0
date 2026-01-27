
import os
import sys
import traceback

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
try:
    import django
    django.setup()
    print("Django setup success")
except Exception:
    print("Django setup failed")
    traceback.print_exc()
    sys.exit(1)

# Check Dependencies
print("Checking dependencies...")
try:
    import pandas as pd
    print("pandas imported:", pd.__version__)
except ImportError:
    print("FAIL: pandas not found")

try:
    import openpyxl
    print("openpyxl imported:", openpyxl.__version__)
except ImportError:
    print("FAIL: openpyxl not found")

# Check View Import
print("Checking View Import...")
try:
    from core.views_api import StudentManagementViewSet
    print("StudentManagementViewSet imported successfully")
except Exception:
    print("FAIL: Could not import StudentManagementViewSet")
    traceback.print_exc()
    sys.exit(1)

# Check Logic (Mock)
print("Checking Logic...")
try:
    import pandas as pd
    # Create dummy dataframe
    data = {
        '학생이름': ['TestUser'],
        '학생 H.P': ['010-1234-5678'],
        '입/퇴원': ['입학'],
        '학년': ['중1'],
        '수업시작일': ['2024-01-01']
    }
    df = pd.DataFrame(data)
    print("DataFrame Created. Mocking iteration...")
    
    # Just run a snippet of the logic to see if it syntax errors or crashes
    view = StudentManagementViewSet()
    # Note: We can't easily call upload_excel without a request, 
    # but we can check if the method exists and if we can run similar logic.
    
    if hasattr(view, 'upload_excel'):
        print("upload_excel method exists")
    else:
        print("FAIL: upload_excel method missing")

except Exception:
    traceback.print_exc()

print("Debug script finished")
