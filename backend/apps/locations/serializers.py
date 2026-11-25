from rest_framework import serializers

from .models import City, Country, Currency


class CurrencySerializer(serializers.ModelSerializer):
    class Meta:
        model = Currency
        fields = ['code', 'name', 'symbol', 'decimal_places']


class CountrySerializer(serializers.ModelSerializer):
    currency_detail = CurrencySerializer(source='currency', read_only=True)

    class Meta:
        model = Country
        fields = [
            'id', 'name', 'iso2', 'phone_code', 'phone_number_length', 'currency', 'currency_detail', 'timezone',
            'default_language', 'supported_languages', 'date_format', 'tax_name', 'tax_rate', 'payment_gateway',
            'emergency_numbers', 'is_active', 'created_at',
        ]


class PublicCountrySerializer(serializers.ModelSerializer):
    """What an unauthenticated app needs for the login screen."""

    currency = CurrencySerializer(read_only=True)

    class Meta:
        model = Country
        fields = ['id', 'name', 'iso2', 'phone_code', 'phone_number_length', 'currency', 'default_language',
                  'supported_languages']


class CitySerializer(serializers.ModelSerializer):
    country_name = serializers.CharField(source='country.name', read_only=True)

    class Meta:
        model = City
        fields = ['id', 'country', 'country_name', 'name', 'state', 'timezone', 'is_active', 'created_at']
