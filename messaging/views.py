from rest_framework import viewsets, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.db.models import Q
from .models import Conversation, Message
from .serializers import ConversationSerializer, MessageSerializer


class ConversationViewSet(viewsets.ModelViewSet):
    """대화방 관리"""
    serializer_class = ConversationSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        user = self.request.user
        return Conversation.objects.filter(
            Q(participant1=user) | Q(participant2=user)
        ).prefetch_related('messages')

    @action(detail=False, methods=['post'])
    def get_or_create(self, request):
        """상대방 ID로 대화방 조회 또는 생성"""
        other_id = request.data.get('other_user_id')
        if not other_id:
            return Response(
                {'error': 'other_user_id is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        user = request.user

        # 기존 대화방 찾기
        conv = Conversation.objects.filter(
            Q(participant1=user, participant2_id=other_id) |
            Q(participant1_id=other_id, participant2=user)
        ).first()

        # 없으면 새로 생성
        if not conv:
            conv = Conversation.objects.create(
                participant1=user,
                participant2_id=other_id
            )

        serializer = self.get_serializer(conv)
        return Response(serializer.data)


class MessageViewSet(viewsets.ModelViewSet):
    """메시지 관리"""
    serializer_class = MessageSerializer
    permission_classes = [IsAuthenticated]

    def get_queryset(self):
        conv_id = self.request.query_params.get('conversation')
        if conv_id:
            return Message.objects.filter(conversation_id=conv_id)
        return Message.objects.none()

    def perform_create(self, serializer):
        conv_id = self.request.data.get('conversation')
        conv = Conversation.objects.get(id=conv_id)

        # 메시지 저장
        serializer.save(sender=self.request.user, conversation=conv)

        # 대화방 타임스탬프 갱신
        conv.save()  # auto_now on last_message_at

    @action(detail=False, methods=['post'])
    def mark_read(self, request):
        """대화방의 상대방 메시지를 모두 읽음 처리"""
        conv_id = request.data.get('conversation')
        if not conv_id:
            return Response(
                {'error': 'conversation is required'},
                status=status.HTTP_400_BAD_REQUEST
            )

        # 내가 보낸 게 아닌 메시지만 읽음 처리
        updated = Message.objects.filter(
            conversation_id=conv_id
        ).exclude(sender=request.user).update(is_read=True)

        return Response({'status': 'ok', 'updated': updated})
