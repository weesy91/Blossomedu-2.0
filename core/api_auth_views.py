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
        print(f"DEBUG: CustomAuthToken Login user={user.username} id={user.id}", flush=True)

        # Determine User Type & Profile Info
        user_type = 'STUDENT'
        position = None
        branch_id = None
        
        if user.is_staff or user.is_superuser:
            user_type = 'TEACHER'
            try:
                profile = getattr(user, 'staff_profile', None)
                print(f"DEBUG: Login Staff Profile: {profile}", flush=True)
                if profile:
                    position = profile.position
                    print(f"DEBUG: Login Position: {position}", flush=True)
                    if profile.branch:
                        branch_id = profile.branch.id
            except Exception as e:
                print(f"DEBUG: Login Profile Error: {e}", flush=True)
            
            # [NEW] Default position for Superuser if no profile
            if not position and user.is_superuser:
               print(f"DEBUG: Login Defaulting Superuser to PRINCIPAL", flush=True)
               position = 'PRINCIPAL'
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
        print(f"DEBUG: CheckAuthView user={user.username}, id={user.id}", flush=True)
        
        # Determine User Type & Profile Info (Same logic as CustomAuthToken)
        user_type = 'STUDENT'
        position = None
        branch_id = None
        
        if user.is_staff or user.is_superuser:
            user_type = 'TEACHER'
            print(f"DEBUG: User is STAFF/SUPERUSER", flush=True)
            try:
                profile = getattr(user, 'staff_profile', None)
                print(f"DEBUG: Staff Profile found: {profile}", flush=True)
                if profile:
                    position = profile.position
                    print(f"DEBUG: Position: {position}", flush=True)
                    if profile.branch:
                        branch_id = profile.branch.id
                        print(f"DEBUG: Branch: {branch_id}", flush=True)
            except Exception as e:
                print(f"DEBUG: Profile Fetch Error: {e}", flush=True)
                pass
            
            # [NEW] Default position for Superuser if no profile
            if not position and user.is_superuser:
               print(f"DEBUG: Defaulting Superuser to PRINCIPAL", flush=True)
               position = 'PRINCIPAL'
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
        print(f"DEBUG: Final User Data: {user_data}", flush=True)

        return Response(user_data)
