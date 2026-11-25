from rest_framework import permissions, viewsets

from apps.core.permissions import IsPlatformAdmin

from .models import City, Country, Currency
from .serializers import CitySerializer, CountrySerializer, CurrencySerializer, PublicCountrySerializer


class PublicCountryViewSet(viewsets.ReadOnlyModelViewSet):
    """Active countries for the app's country picker (no login needed)."""

    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    serializer_class = PublicCountrySerializer
    queryset = Country.objects.filter(is_active=True).select_related('currency')
    pagination_class = None


class CurrencyAdminViewSet(viewsets.ModelViewSet):
    permission_classes = [IsPlatformAdmin]
    serializer_class = CurrencySerializer
    queryset = Currency.objects.all()
    search_fields = ['code', 'name']


class CountryAdminViewSet(viewsets.ModelViewSet):
    permission_classes = [IsPlatformAdmin]
    serializer_class = CountrySerializer
    queryset = Country.objects.select_related('currency')
    search_fields = ['name', 'iso2']
    filterset_fields = ['is_active', 'currency']


class CityAdminViewSet(viewsets.ModelViewSet):
    permission_classes = [IsPlatformAdmin]
    serializer_class = CitySerializer
    queryset = City.objects.select_related('country')
    search_fields = ['name', 'state']
    filterset_fields = ['country', 'is_active']
