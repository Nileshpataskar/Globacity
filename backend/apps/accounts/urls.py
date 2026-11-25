from django.urls import path
from drf_spectacular.utils import extend_schema, extend_schema_view
from rest_framework_simplejwt.views import TokenRefreshView

from . import views

RefreshView = extend_schema_view(post=extend_schema(tags=['Auth']))(TokenRefreshView)

urlpatterns = [
    path('auth/otp/request/', views.OTPRequestView.as_view(), name='otp-request'),
    path('auth/otp/verify/', views.OTPVerifyView.as_view(), name='otp-verify'),
    path('auth/login/', views.PasswordLoginView.as_view(), name='password-login'),
    path('auth/token/refresh/', RefreshView.as_view(), name='token-refresh'),
    path('auth/logout/', views.LogoutView.as_view(), name='logout'),
    path('auth/password/forgot/', views.ForgotPasswordView.as_view(), name='password-forgot'),
    path('auth/password/reset/', views.ResetPasswordView.as_view(), name='password-reset'),
    path('me/', views.MeView.as_view(), name='me'),
    path('me/settings/', views.MeSettingsView.as_view(), name='me-settings'),
    path('me/password/', views.ChangePasswordView.as_view(), name='me-password'),
]
