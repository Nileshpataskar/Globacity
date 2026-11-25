from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Notification(BaseModel):
    class Category(models.TextChoices):
        GATE = 'gate'
        DAILY_HELP = 'daily_help'
        PAYMENT = 'payment'
        NOTICE = 'notice'
        COMMUNITY = 'community'
        HELPDESK = 'helpdesk'
        SECURITY = 'security'
        MESSAGE = 'message'
        GENERAL = 'general'

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='notifications')
    title = models.CharField(max_length=150)
    body = models.TextField(blank=True)
    category = models.CharField(max_length=20, choices=Category.choices, default=Category.GENERAL)
    data = models.JSONField(default=dict, blank=True, help_text='Deep-link payload, e.g. {"visitor_id": "..."}')
    is_read = models.BooleanField(default=False)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['user', 'is_read'])]

    def __str__(self):
        return self.title


class Device(BaseModel):
    """Push token (FCM is free). Sending is a no-op until FCM credentials are configured."""

    class Platform(models.TextChoices):
        ANDROID = 'android'
        IOS = 'ios'
        WEB = 'web'

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='devices')
    token = models.CharField(max_length=255, unique=True)
    platform = models.CharField(max_length=10, choices=Platform.choices)
