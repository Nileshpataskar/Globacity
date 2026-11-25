from datetime import timedelta
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env(DEBUG=(bool, False), CORS_ALLOW_ALL=(bool, False))
environ.Env.read_env(BASE_DIR / '.env')

DEBUG = env('DEBUG')
SECRET_KEY = env('SECRET_KEY', default='dev-only-insecure-key')
ALLOWED_HOSTS = env.list('ALLOWED_HOSTS', default=['*'])

INSTALLED_APPS = [
    'daphne',
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    # Third party
    'rest_framework',
    'rest_framework_simplejwt.token_blacklist',
    'drf_spectacular',
    'django_filters',
    'corsheaders',
    'channels',
    # Project
    'apps.core',
    'apps.accounts',
    'apps.locations',
    'apps.communities',
    'apps.household',
    'apps.gate',
    'apps.finance',
    'apps.engagement',
    'apps.helpdesk',
    'apps.notifications',
    'apps.messaging',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'whitenoise.middleware.WhiteNoiseMiddleware',  # serves admin / API-docs CSS in production
    'corsheaders.middleware.CorsMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'config.urls'
WSGI_APPLICATION = 'config.wsgi.application'
ASGI_APPLICATION = 'config.asgi.application'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

DATABASES = {'default': env.db('DATABASE_URL', default='postgres://globacity:globacity@localhost:5432/globacity')}
DATABASES['default']['CONN_MAX_AGE'] = env.int('DB_CONN_MAX_AGE', default=60)
DATABASES['default']['CONN_HEALTH_CHECKS'] = True
# Neon's "-pooler" host is PgBouncer in transaction mode: server-side cursors must be off.
if '-pooler.' in str(DATABASES['default'].get('HOST', '')):
    DATABASES['default']['DISABLE_SERVER_SIDE_CURSORS'] = True
DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'

AUTH_USER_MODEL = 'accounts.User'
AUTH_PASSWORD_VALIDATORS = [
    {'NAME': 'django.contrib.auth.password_validation.MinimumLengthValidator', 'OPTIONS': {'min_length': 8}},
    {'NAME': 'django.contrib.auth.password_validation.CommonPasswordValidator'},
]

LANGUAGE_CODE = 'en'
TIME_ZONE = 'UTC'  # Stored in UTC; each community/country carries its own timezone.
USE_I18N = True
USE_TZ = True

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STORAGES = {
    'default': {'BACKEND': 'django.core.files.storage.FileSystemStorage'},
    'staticfiles': {'BACKEND': 'whitenoise.storage.CompressedManifestStaticFilesStorage'},
}
# Serve uploaded photos from Django itself (fine for a demo host; use object storage for real production).
SERVE_MEDIA = env.bool('SERVE_MEDIA', default=False)

# ---------------------------------------------------------------------------
# Hosting behind HTTPS (Render, etc.)
# ---------------------------------------------------------------------------
SECURE_PROXY_SSL_HEADER = ('HTTP_X_FORWARDED_PROTO', 'https')
CSRF_TRUSTED_ORIGINS = env.list('CSRF_TRUSTED_ORIGINS', default=[])
_render_host = env('RENDER_EXTERNAL_HOSTNAME', default='')
if _render_host:
    ALLOWED_HOSTS = [*ALLOWED_HOSTS, _render_host]
    CSRF_TRUSTED_ORIGINS = [*CSRF_TRUSTED_ORIGINS, f'https://{_render_host}']
MEDIA_URL = 'media/'
MEDIA_ROOT = BASE_DIR / 'media'

# ---------------------------------------------------------------------------
# API
# ---------------------------------------------------------------------------

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': [
        'rest_framework_simplejwt.authentication.JWTAuthentication',
        'rest_framework.authentication.SessionAuthentication',
    ],
    'DEFAULT_PERMISSION_CLASSES': ['rest_framework.permissions.IsAuthenticated'],
    'DEFAULT_FILTER_BACKENDS': [
        'django_filters.rest_framework.DjangoFilterBackend',
        'rest_framework.filters.SearchFilter',
        'rest_framework.filters.OrderingFilter',
    ],
    'DEFAULT_PAGINATION_CLASS': 'apps.core.pagination.StandardPagination',
    'DEFAULT_SCHEMA_CLASS': 'apps.core.schema.AppAutoSchema',
    'DEFAULT_THROTTLE_RATES': {'otp': '5/min'},
}

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(hours=12),
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': True,
}

SPECTACULAR_SETTINGS = {
    'TITLE': 'Globacity API',
    'DESCRIPTION': (
        'Community management platform API.\n\n'
        '**Auth:** call `/api/v1/auth/otp/request/` then `/api/v1/auth/otp/verify/` (in DEBUG the OTP is returned '
        'in the response), then click **Authorize** and paste the `access` token.\n\n'
        '**Resident endpoints** act on one unit: send its id in the `X-Unit-ID` header '
        '(optional when you belong to exactly one unit).\n\n'
        '**Manage endpoints** are for community admins/managers; **Platform endpoints** are for platform admins.'
    ),
    'VERSION': '1.0.0',
    'SERVE_INCLUDE_SCHEMA': False,
    'COMPONENT_SPLIT_REQUEST': True,
    'SCHEMA_PATH_PREFIX': r'/api/v1',
    'SWAGGER_UI_SETTINGS': {'persistAuthorization': True, 'docExpansion': 'none', 'filter': True},
    'ENUM_NAME_OVERRIDES': {
        'MembershipStatusEnum': 'apps.communities.models.Membership.Status',
        'MembershipRoleEnum': 'apps.communities.models.Membership.Role',
        'StaffRoleEnum': 'apps.communities.models.StaffMember.Role',
        'VisitorStatusEnum': 'apps.gate.models.Visitor.Status',
        'KidExitStatusEnum': 'apps.gate.models.KidExitPermission.Status',
        'SOSStatusEnum': 'apps.gate.models.SOSAlert.Status',
        'InvoiceStatusEnum': 'apps.finance.models.Invoice.Status',
        'PaymentStatusEnum': 'apps.finance.models.Payment.Status',
        'ClassifiedStatusEnum': 'apps.engagement.models.Classified.Status',
        'BookingStatusEnum': 'apps.engagement.models.ServiceBooking.Status',
        'MoveRequestStatusEnum': 'apps.engagement.models.MoveRequest.Status',
        'TicketStatusEnum': 'apps.helpdesk.models.Ticket.Status',
    },
}

CORS_ALLOW_ALL_ORIGINS = env('CORS_ALLOW_ALL')
CORS_ALLOW_HEADERS = (
    'accept', 'authorization', 'content-type', 'origin', 'user-agent', 'x-csrftoken', 'x-requested-with', 'x-unit-id',
)

# ---------------------------------------------------------------------------
# Realtime (WebSockets). Redis in Docker; in-memory fallback when unset.
# ---------------------------------------------------------------------------

REDIS_URL = env('REDIS_URL', default='')
CHANNEL_LAYERS = (
    {'default': {'BACKEND': 'channels_redis.core.RedisChannelLayer', 'CONFIG': {'hosts': [REDIS_URL]}}}
    if REDIS_URL
    else {'default': {'BACKEND': 'channels.layers.InMemoryChannelLayer'}}
)

# ---------------------------------------------------------------------------
# Pluggable providers (all free by default)
# ---------------------------------------------------------------------------

OTP_TTL_SECONDS = env.int('OTP_TTL_SECONDS', default=300)
# Return the OTP in the API response (no SMS provider yet). Defaults to DEBUG. Turn off once real SMS is set up:
# while on, anyone who knows a phone number can sign in as that user.
OTP_SHOW_CODE = env.bool('OTP_SHOW_CODE', default=DEBUG)
IOT_GATE_DRIVER = env('IOT_GATE_DRIVER', default='apps.gate.iot.MockGateDriver')
OTP_MAX_ATTEMPTS = 5
SMS_BACKEND = env('SMS_BACKEND', default='apps.accounts.sms.ConsoleSMSBackend')
EMAIL_BACKEND = env('EMAIL_BACKEND', default='django.core.mail.backends.console.EmailBackend')
DEFAULT_FROM_EMAIL = env('DEFAULT_FROM_EMAIL', default='no-reply@globacity.local')

LOGGING = {
    'version': 1,
    'disable_existing_loggers': False,
    'handlers': {'console': {'class': 'logging.StreamHandler'}},
    'loggers': {'apps': {'handlers': ['console'], 'level': 'INFO'}},
}
