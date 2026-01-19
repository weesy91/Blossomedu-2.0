from django.db import models
from django.conf import settings

class Message(models.Model):
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='sent_messages', verbose_name="보낸 사람")
    receiver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='received_messages', verbose_name="받는 사람")
    
    content = models.TextField(verbose_name="메시지 내용")
    image = models.ImageField(upload_to='messages/%Y/%m/%d/', null=True, blank=True, verbose_name="첨부 이미지")
    
    sent_at = models.DateTimeField(auto_now_add=True, verbose_name="보낸 시간")
    read_at = models.DateTimeField(null=True, blank=True, verbose_name="읽은 시간")
    
    class Meta:
        ordering = ['-sent_at']
        verbose_name = "메시지"
        verbose_name_plural = "메시지"

    def __str__(self):
        return f"{self.sender} -> {self.receiver}: {self.content[:20]}"
