from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('notifications', views.NotificationViewSet, basename='notification')
router.register('devices', views.DeviceViewSet, basename='device')

urlpatterns = router.urls
