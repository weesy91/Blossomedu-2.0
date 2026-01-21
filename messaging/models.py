from django.db import models
from django.contrib.auth import get_user_model

User = get_user_model()


class Conversation(models.Model):
    """1:1 대화방 (학생 <-> 선생님)"""
    participant1 = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='conversations_as_p1'
    )
    participant2 = models.ForeignKey(
        User, on_delete=models.CASCADE, related_name='conversations_as_p2'
    )
    last_message_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-last_message_at']

    def __str__(self):
        return f"Conv: {self.participant1} <-> {self.participant2}"

    def get_other_participant(self, user):
        """현재 사용자 기준으로 상대방 반환"""
        if self.participant1_id == user.id:
            return self.participant2
        return self.participant1


class Message(models.Model):
    """개별 메시지"""
    conversation = models.ForeignKey(
        Conversation, on_delete=models.CASCADE, related_name='messages'
    )
    sender = models.ForeignKey(User, on_delete=models.CASCADE)
    content = models.TextField()
    is_read = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['created_at']

    def __str__(self):
        return f"{self.sender}: {self.content[:30]}"
