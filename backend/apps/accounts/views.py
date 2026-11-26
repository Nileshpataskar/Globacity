import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.tokens import default_token_generator
from django.core.mail import send_mail
from django.utils import timezone
from django.utils.encoding import force_bytes, force_str
from django.utils.http import urlsafe_base64_decode, urlsafe_base64_encode
from drf_spectacular.utils import extend_schema
from rest_framework import generics, permissions, status
from rest_framework.exceptions import AuthenticationFailed, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken

from .models import OTPCode, User, UserSettings, hash_code
from .phone import normalize_phone
from .serializers import (
    AuthResponseSerializer,
    ChangePasswordSerializer,
    DetailSerializer,
    ForgotPasswordSerializer,
    OTPRequestResponseSerializer,
    OTPRequestSerializer,
    OTPVerifySerializer,
    PasswordLoginSerializer,
    RefreshSerializer,
    ResetPasswordSerializer,
    UserSerializer,
    UserSettingsSerializer,
)
from .sms import send_sms


def auth_payload(user, is_new_user=False):
    refresh = RefreshToken.for_user(user)
    return {
        'access': str(refresh.access_token),
        'refresh': str(refresh),
        'is_new_user': is_new_user,
        'user': UserSerializer(user).data,
    }


class OTPRequestView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_scope = 'otp'

    @extend_schema(request=OTPRequestSerializer, responses=OTPRequestResponseSerializer, tags=['Auth'])
    def post(self, request):
        s = OTPRequestSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        phone, _ = normalize_phone(s.validated_data['phone'])
        purpose = s.validated_data.get('purpose')
        existing = User.objects.filter(phone=phone).first()
        if purpose == 'login' and existing is None:
            return Response({'code': 'not_registered',
                             'detail': 'This number is not registered yet. Please sign up first.'}, status=404)
        if purpose == 'login' and not existing.is_active:
            return Response({'code': 'disabled', 'detail': 'This account is disabled. Contact your community office.'},
                            status=403)
        if purpose == 'signup' and existing is not None:
            return Response({'code': 'already_registered',
                             'detail': 'This number is already registered. Please sign in instead.'}, status=409)
        code = f'{secrets.randbelow(1_000_000):06d}'
        OTPCode.objects.filter(phone=phone, is_used=False).update(is_used=True)
        OTPCode.objects.create(
            phone=phone, code_hash=hash_code(code),
            expires_at=timezone.now() + timedelta(seconds=settings.OTP_TTL_SECONDS),
        )
        send_sms(phone, f'Your verification code is {code}')
        body = {'detail': 'Verification code sent.', 'expires_in': settings.OTP_TTL_SECONDS}
        if settings.OTP_SHOW_CODE:
            body['debug_code'] = code
        return Response(body)


class OTPVerifyView(APIView):
    """Verifies the OTP and signs in. Creates the account on first login."""

    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    @extend_schema(request=OTPVerifySerializer, responses=AuthResponseSerializer, tags=['Auth'])
    def post(self, request):
        s = OTPVerifySerializer(data=request.data)
        s.is_valid(raise_exception=True)
        phone, country = normalize_phone(s.validated_data['phone'])
        otp = OTPCode.objects.filter(phone=phone, is_used=False).first()
        if otp is None or otp.is_expired:
            raise ValidationError({'code': 'Code expired. Request a new one.'})
        if otp.attempts >= settings.OTP_MAX_ATTEMPTS:
            raise ValidationError({'code': 'Too many attempts. Request a new code.'})
        if not otp.matches(s.validated_data['code']):
            otp.attempts += 1
            otp.save(update_fields=['attempts'])
            raise ValidationError({'code': 'Incorrect code.'})
        otp.is_used = True
        otp.save(update_fields=['is_used'])

        if s.validated_data.get('purpose') == 'login' and not User.objects.filter(phone=phone).exists():
            return Response({'code': 'not_registered',
                             'detail': 'This number is not registered yet. Please sign up first.'}, status=404)
        user, created = User.objects.get_or_create(
            phone=phone,
            defaults={
                'full_name': s.validated_data.get('full_name', ''),
                'country': country,
                'language': country.default_language,
            },
        )
        if created:
            user.set_unusable_password()
            user.save(update_fields=['password'])
        if not user.is_active:
            raise AuthenticationFailed('This account is disabled.')
        return Response(auth_payload(user, is_new_user=created))


class PasswordLoginView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    @extend_schema(request=PasswordLoginSerializer, responses=AuthResponseSerializer, tags=['Auth'])
    def post(self, request):
        s = PasswordLoginSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        ident = s.validated_data['identifier'].strip()
        lookup = {'email__iexact': ident} if '@' in ident else {'phone': ident.replace(' ', '')}
        user = User.objects.filter(**lookup).first()
        if not user or not user.is_active or not user.check_password(s.validated_data['password']):
            raise AuthenticationFailed('Invalid credentials.')
        return Response(auth_payload(user))


class LogoutView(APIView):
    @extend_schema(request=RefreshSerializer, responses=DetailSerializer, tags=['Auth'])
    def post(self, request):
        s = RefreshSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            RefreshToken(s.validated_data['refresh']).blacklist()
        except TokenError:
            pass
        return Response({'detail': 'Logged out.'})


class ForgotPasswordView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_scope = 'otp'

    @extend_schema(request=ForgotPasswordSerializer, responses=DetailSerializer, tags=['Auth'])
    def post(self, request):
        s = ForgotPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = User.objects.filter(email__iexact=s.validated_data['email'], is_active=True).first()
        if user:
            uid = urlsafe_base64_encode(force_bytes(user.pk))
            token = default_token_generator.make_token(user)
            send_mail(
                'Reset your password',
                f'Use these values in the app to reset your password.\nuid: {uid}\ntoken: {token}',
                settings.DEFAULT_FROM_EMAIL,
                [user.email],
            )
        return Response({'detail': 'If that email is registered, a reset link has been sent.'})


class ResetPasswordView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    @extend_schema(request=ResetPasswordSerializer, responses=DetailSerializer, tags=['Auth'])
    def post(self, request):
        s = ResetPasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        try:
            user = User.objects.get(pk=force_str(urlsafe_base64_decode(s.validated_data['uid'])))
        except (User.DoesNotExist, ValueError, TypeError, OverflowError):
            raise ValidationError({'uid': 'Invalid reset link.'})
        if not default_token_generator.check_token(user, s.validated_data['token']):
            raise ValidationError({'token': 'Reset link is invalid or has expired.'})
        user.set_password(s.validated_data['new_password'])
        user.save(update_fields=['password'])
        return Response({'detail': 'Password updated.'})


class ChangePasswordView(APIView):
    @extend_schema(request=ChangePasswordSerializer, responses=DetailSerializer, tags=['Me'])
    def post(self, request):
        s = ChangePasswordSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        user = request.user
        has_password = bool(user.password) and user.has_usable_password()
        if has_password and not user.check_password(s.validated_data.get('old_password', '')):
            raise ValidationError({'old_password': 'Incorrect password.'})
        user.set_password(s.validated_data['new_password'])
        user.save(update_fields=['password'])
        return Response({'detail': 'Password updated.'}, status=status.HTTP_200_OK)


class MeView(generics.RetrieveUpdateAPIView):
    """Profile. PATCH as JSON, or multipart with an ``avatar`` file to upload a photo."""

    serializer_class = UserSerializer
    http_method_names = ['get', 'patch']
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_object(self):
        return self.request.user


class MeSettingsView(generics.RetrieveUpdateAPIView):
    serializer_class = UserSettingsSerializer
    http_method_names = ['get', 'patch']

    def get_object(self):
        return UserSettings.for_user(self.request.user)
