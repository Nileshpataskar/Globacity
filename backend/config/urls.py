from django.conf import settings
from django.conf.urls.static import static
from django.contrib import admin
from django.urls import include, path
from django.views.generic import RedirectView
from drf_spectacular.views import SpectacularAPIView, SpectacularRedocView, SpectacularSwaggerView

admin.site.site_header = 'Globacity Platform Admin'
admin.site.site_title = 'Globacity Admin'

api_v1 = [
    path('', include('apps.core.urls')),
    path('', include('apps.accounts.urls')),
    path('', include('apps.locations.urls')),
    path('', include('apps.communities.urls')),
    path('', include('apps.household.urls')),
    path('', include('apps.gate.urls')),
    path('', include('apps.finance.urls')),
    path('', include('apps.engagement.urls')),
    path('', include('apps.helpdesk.urls')),
    path('', include('apps.notifications.urls')),
    path('', include('apps.messaging.urls')),
]

urlpatterns = [
    path('', RedirectView.as_view(url='/api/docs/', permanent=False)),
    path('admin/', admin.site.urls),
    path('api/v1/', include(api_v1)),
    path('api/schema/', SpectacularAPIView.as_view(), name='schema'),
    path('api/docs/', SpectacularSwaggerView.as_view(url_name='schema'), name='swagger-ui'),
    path('api/redoc/', SpectacularRedocView.as_view(url_name='schema'), name='redoc'),
] + static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)

if settings.SERVE_MEDIA and not settings.DEBUG:
    from django.urls import re_path
    from django.views.static import serve

    urlpatterns += [re_path(r'^media/(?P<path>.*)$', serve, {'document_root': settings.MEDIA_ROOT})]
