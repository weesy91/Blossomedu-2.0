from rest_framework.authtoken.views import ObtainAuthToken
from rest_framework.authtoken.models import Token
from rest_framework.authentication import TokenAuthentication
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView


def _build_user_data(user):
    user_type = 'STUDENT'
    position = None
    branch_id = None
    student_id = None
    name = user.username

    try:
        staff_profile = getattr(user, 'staff_profile', None)
        if staff_profile and staff_profile.name:
            name = staff_profile.name
    except Exception:
        pass

    if user.is_staff or user.is_superuser:
        user_type = 'TEACHER'
        try:
            profile = getattr(user, 'staff_profile', None)
            if profile:
                position = profile.position
                if profile.branch:
                    branch_id = profile.branch.id
        except Exception as e:
            print(f"Profile Fetch Error: {e}")
    else:
        try:
            profile = getattr(user, 'profile', None)
            if profile:
                if profile.name:
                    name = profile.name
                student_id = profile.id
        except Exception:
            pass

    if name == user.username and user.first_name:
        name = user.first_name

    return {
        'id': user.id,
        'username': user.username,
        'name': name,
        'user_type': user_type,
        'is_superuser': user.is_superuser,
        'position': position,
        'branch_id': branch_id,
        'student_id': student_id,
    }

from rest_framework.permissions import IsAuthenticated, AllowAny # [Added AllowAny]

# ...

class CustomAuthToken(ObtainAuthToken):
    # [FIX] Disable SessionAuth to prevent CSRF errors when browser sends cookies
    authentication_classes = [] 
    permission_classes = [AllowAny]

    def post(self, request, *args, **kwargs):
        serializer = self.serializer_class(data=request.data,
                                           context={'request': request})
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        token, created = Token.objects.get_or_create(user=user)
        user_data = _build_user_data(user)

        return Response({
            'token': token.key,
            'user': user_data
        })


class CheckAuthView(APIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request, *args, **kwargs):
        user_data = _build_user_data(request.user)
        token = request.auth
        return Response({
            'token': token.key if token else None,
            'user': user_data,
        })
