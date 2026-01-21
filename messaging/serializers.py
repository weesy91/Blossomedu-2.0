from rest_framework import serializers
from .models import Conversation, Message


class MessageSerializer(serializers.ModelSerializer):
    sender_name = serializers.SerializerMethodField()
    is_mine = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = ['id', 'content', 'sender', 'sender_name', 'is_mine', 'is_read', 'created_at']
        read_only_fields = ['sender', 'is_read', 'created_at']

    def get_sender_name(self, obj):
        # Try to get name from profile first, fallback to username
        if hasattr(obj.sender, 'profile') and obj.sender.profile:
            return obj.sender.profile.name or obj.sender.first_name or obj.sender.username
        return obj.sender.first_name or obj.sender.username

    def get_is_mine(self, obj):
        request = self.context.get('request')
        return request and obj.sender_id == request.user.id


class ConversationSerializer(serializers.ModelSerializer):
    other_user_id = serializers.SerializerMethodField()
    other_user_name = serializers.SerializerMethodField()
    last_message = serializers.SerializerMethodField()
    unread_count = serializers.SerializerMethodField()

    class Meta:
        model = Conversation
        fields = ['id', 'other_user_id', 'other_user_name', 'last_message', 'unread_count', 'last_message_at']

    def _get_other_user(self, obj):
        request = self.context.get('request')
        return obj.get_other_participant(request.user)

    def get_other_user_id(self, obj):
        return self._get_other_user(obj).id

    def get_other_user_name(self, obj):
        other = self._get_other_user(obj)
        if hasattr(other, 'profile') and other.profile:
            return other.profile.name or other.first_name or other.username
        return other.first_name or other.username

    def get_last_message(self, obj):
        msg = obj.messages.last()
        if msg:
            return msg.content[:50]
        return None

    def get_unread_count(self, obj):
        request = self.context.get('request')
        return obj.messages.filter(is_read=False).exclude(sender=request.user).count()
