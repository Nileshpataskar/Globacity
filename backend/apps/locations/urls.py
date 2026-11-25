from rest_framework.routers import DefaultRouter

from . import views

router = DefaultRouter()
router.register('countries', views.PublicCountryViewSet, basename='public-country')
router.register('platform/currencies', views.CurrencyAdminViewSet, basename='platform-currency')
router.register('platform/countries', views.CountryAdminViewSet, basename='platform-country')
router.register('platform/cities', views.CityAdminViewSet, basename='platform-city')

urlpatterns = router.urls
