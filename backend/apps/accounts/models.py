import hashlib
import uuid

from django.conf import settings
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin
from django.db import models
from django.utils import timezone

DEFAULT_NOTIFICATION_PREFS = {
    'visitor_at_gate': True,
    'daily_help_entry': True,
    'deliveries': True,
    'notices': True,
    'payment_reminders': True,
    'polls_events': False,
    'forum_replies': False,
    'helpdesk_updates': True,
}

DEFAULT_PRIVACY_PREFS = {
    'show_in_directory': True,
    'show_phone': False,
    'show_unit': True,
    'allow_messages': True,
    'allow_guard_calls': True,
}


def default_notification_prefs():
    return dict(DEFAULT_NOTIFICATION_PREFS)


def default_privacy_prefs():
    return dict(DEFAULT_PRIVACY_PREFS)


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, phone, password=None, **extra):
        if not phone:
            raise ValueError('Phone is required')
        user = self.model(phone=phone, **extra)
        if password:
            user.set_password(password)
        else:
            user.set_unusable_password()
        user.save(using=self._db)
        return user

    def create_superuser(self, phone, password, **extra):
        extra.setdefault('is_staff', True)
        extra.setdefault('is_superuser', True)
        return self.create_user(phone, password, **extra)


class User(AbstractBaseUser, PermissionsMixin):
    """Phone-first user (E.164, e.g. +971501234567). Email is optional."""

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    phone = models.CharField(max_length=20, unique=True)
    email = models.EmailField(unique=True, null=True, blank=True)
    full_name = models.CharField(max_length=150, blank=True)
    avatar = models.ImageField(upload_to='avatars/', null=True, blank=True)
    country = models.ForeignKey('locations.Country', on_delete=models.SET_NULL, null=True, blank=True)
    language = models.CharField(max_length=8, default='en')
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False, help_text='Platform admin: can manage countries and communities.')
    date_joined = models.DateTimeField(default=timezone.now)

    objects = UserManager()

    USERNAME_FIELD = 'phone'
    REQUIRED_FIELDS = ['full_name']

    class Meta:
        ordering = ['full_name']

    def __str__(self):
        return self.full_name or self.phone

    def save(self, *args, **kwargs):
        if not self.email:
            self.email = None
        super().save(*args, **kwargs)


class UserSettings(models.Model):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name='app_settings')
    notification_prefs = models.JSONField(default=default_notification_prefs)
    privacy_prefs = models.JSONField(default=default_privacy_prefs)

    class Meta:
        verbose_name_plural = 'user settings'

    @classmethod
    def for_user(cls, user):
        obj, _ = cls.objects.get_or_create(user=user)
        return obj


def hash_code(code: str) -> str:
    return hashlib.sha256(f'{settings.SECRET_KEY}:{code}'.encode()).hexdigest()


class OTPCode(models.Model):
    phone = models.CharField(max_length=20, db_index=True)
    code_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField()
    attempts = models.PositiveSmallIntegerField(default=0)
    is_used = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    @property
    def is_expired(self):
        return timezone.now() >= self.expires_at

    def matches(self, code: str) -> bool:
        return self.code_hash == hash_code(code)
