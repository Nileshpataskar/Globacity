from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('household/family', views.FamilyMemberViewSet, basename='family')
router.register('household/vehicles', views.VehicleViewSet, basename='vehicle')
router.register('household/pets', views.PetViewSet, basename='pet')
router.register('household/daily-help', views.DailyHelpViewSet, basename='daily-help')

urlpatterns = router.urls
