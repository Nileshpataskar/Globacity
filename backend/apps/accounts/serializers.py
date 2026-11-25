from django.contrib.auth.password_validation import validate_password
from rest_framework import serializers

from .models import DEFAULT_NOTIFICATION_PREFS, DEFAULT_PRIVACY_PREFS, User, UserSettings


class UserSerializer(serializers.ModelSerializer):
    is_platform_admin = serializers.BooleanField(source='is_staff', read_only=True)
    has_password = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = ['id', 'phone', 'email', 'full_name', 'avatar', 'country', 'language', 'is_platform_admin',
                  'has_password', 'date_joined']
        read_only_fields = ['id', 'phone', 'country', 'date_joined']

    def get_has_password(self, obj) -> bool:
        return bool(obj.password) and obj.has_usable_password()


class UserMiniSerializer(serializers.ModelSerializer):
    class Meta:
        model = User
        fields = ['id', 'full_name', 'phone', 'avatar']


class OTPRequestSerializer(serializers.Serializer):
    phone = serializers.CharField(help_text='International format, e.g. +971501234567')


class OTPRequestResponseSerializer(serializers.Serializer):
    detail = serializers.CharField()
    expires_in = serializers.IntegerField()
    debug_code = serializers.CharField(required=False, help_text='Only returned when DEBUG=true')


class OTPVerifySerializer(serializers.Serializer):
    phone = serializers.CharField()
    code = serializers.CharField(min_length=6, max_length=6)
    full_name = serializers.CharField(required=False, allow_blank=True, help_text='Used when creating a new account')


class AuthResponseSerializer(serializers.Serializer):
    access = serializers.CharField()
    refresh = serializers.CharField()
    is_new_user = serializers.BooleanField()
    user = UserSerializer()


class PasswordLoginSerializer(serializers.Serializer):
    identifier = serializers.CharField(help_text='Email or phone (+971...)')
    password = serializers.CharField()


class RefreshSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class ForgotPasswordSerializer(serializers.Serializer):
    email = serializers.EmailField()


class ResetPasswordSerializer(serializers.Serializer):
    uid = serializers.CharField()
    token = serializers.CharField()
    new_password = serializers.CharField(validators=[validate_password])


class ChangePasswordSerializer(serializers.Serializer):
    old_password = serializers.CharField(required=False, allow_blank=True)
    new_password = serializers.CharField(validators=[validate_password])


class DetailSerializer(serializers.Serializer):
    detail = serializers.CharField()


def _validate_prefs(value, defaults, field):
    if not isinstance(value, dict):
        raise serializers.ValidationError('Must be an object.')
    unknown = set(value) - set(defaults)
    if unknown:
        raise serializers.ValidationError(f'Unknown keys: {", ".join(sorted(unknown))}')
    if not all(isinstance(v, bool) for v in value.values()):
        raise serializers.ValidationError('Values must be true/false.')
    return value


class UserSettingsSerializer(serializers.ModelSerializer):
    class Meta:
        model = UserSettings
        fields = ['notification_prefs', 'privacy_prefs']

    def validate_notification_prefs(self, value):
        return _validate_prefs(value, DEFAULT_NOTIFICATION_PREFS, 'notification_prefs')

    def validate_privacy_prefs(self, value):
        return _validate_prefs(value, DEFAULT_PRIVACY_PREFS, 'privacy_prefs')

    def update(self, instance, validated_data):
        # Merge partial updates instead of replacing the whole object.
        for field in ('notification_prefs', 'privacy_prefs'):
            if field in validated_data:
                setattr(instance, field, {**getattr(instance, field), **validated_data[field]})
        instance.save()
        return instance
