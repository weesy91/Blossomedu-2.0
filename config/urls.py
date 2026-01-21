from django.contrib import admin
from django.urls import path, include
from django.conf import settings  
from django.conf.urls.static import static
from django.contrib.auth import views as auth_views 
from core.api_auth_views import CustomAuthToken, CheckAuthView # [Changed]

# ... existing code ...

urlpatterns = [
    path('admin/', admin.site.urls),

    # 1. 접속하자마자 로그인 화면 보여주기
    path('', auth_views.LoginView.as_view(template_name='core/login.html'), name='root_login'),

    # [NEW] API Login Endpoint (matches AuthService)
    path('auth/login/', CustomAuthToken.as_view(), name='api_login'),
    path('auth/me/', CheckAuthView.as_view(), name='api_me'), # [NEW]

    # 2. 나머지 앱들 연결
    path('core/', include(('core.urls', 'core'), namespace='core')),
    path('vocab/', include('vocab.urls')), # API URLs included inside
    path('academy/', include('academy.urls')),
    path('reports/', include('reports.urls')),
    path('exam/', include('exam.urls')),
    path('mock/', include('mock.urls')),
    path('messaging/', include('messaging.urls')),  # [NEW] 메시지 API
]

if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)