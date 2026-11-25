from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Conversation(BaseModel):
    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='conversations')
    participants = models.ManyToManyField(settings.AUTH_USER_MODEL, through='Participant', related_name='conversations')
    last_message_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-last_message_at', '-created_at']


class Participant(models.Model):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='memberships')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    last_read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['conversation', 'user'], name='unique_participant')]


class Message(BaseModel):
    conversation = models.ForeignKey(Conversation, on_delete=models.CASCADE, related_name='messages')
    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    body = models.TextField()

    class Meta:
        ordering = ['created_at']
