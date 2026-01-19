from rest_framework.authtoken.views import ObtainAuthToken
from rest_framework.authtoken.models import Token
from rest_framework.response import Response

class CustomAuthToken(ObtainAuthToken):
    def post(self, request, *args, **kwargs):
        serializer = self.serializer_class(data=request.data,
                                           context={'request': request})
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data['user']
        token, created = Token.objects.get_or_create(user=user)
        
        # Determine User Type & Profile Info
        user_type = 'STUDENT'
        position = None
        branch_id = None
        
        if user.is_staff or user.is_superuser:
            user_type = 'TEACHER'
            # Fetch Staff Profile
            try:
                # Assuming related_name='staff_profile' from OneToOneField
                profile = getattr(user, 'staff_profile', None)
                if profile:
                    position = profile.position
                    if profile.branch:
                        branch_id = profile.branch.id
            except Exception as e:
                print(f"Profile Fetch Error: {e}")
        else:
            # Student Profile Name Fetch
            try:
                profile = getattr(user, 'profile', None)
                if profile and profile.name:
                   user.first_name = profile.name # Temporarily set for user_data
            except Exception:
                pass

        user_data = {
            'id': user.id,
            'username': user.username,
            'name': user.first_name if user.first_name else user.username,
            'user_type': user_type,
            'is_superuser': user.is_superuser, 
            'position': position, # [NEW]
            'branch_id': branch_id, # [NEW]
        }

        return Response({
            'token': token.key,
            'user': user_data
        })

from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.authentication import TokenAuthentication

class CheckAuthView(APIView):
    authentication_classes = [TokenAuthentication]
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        
        # Determine User Type & Profile Info (Same logic as CustomAuthToken)
        user_type = 'STUDENT'
        position = None
        branch_id = None
        
        if user.is_staff or user.is_superuser:
            user_type = 'TEACHER'
            try:
                profile = getattr(user, 'staff_profile', None)
                if profile:
                    position = profile.position
                    if profile.branch:
                        branch_id = profile.branch.id
            except Exception:
                pass
        else:
            try:
                profile = getattr(user, 'profile', None)
                if profile and profile.name:
                   user.first_name = profile.name
            except Exception:
                pass

        user_data = {
            'id': user.id,
            'username': user.username,
            'name': user.first_name if user.first_name else user.username,
            'user_type': user_type,
            'is_superuser': user.is_superuser,
            'position': position,
            'branch_id': branch_id,
        }

        return Response(user_data)
