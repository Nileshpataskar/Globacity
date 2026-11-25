from django.contrib import admin

from .models import City, Country, Currency


@admin.register(Currency)
class CurrencyAdmin(admin.ModelAdmin):
    list_display = ['code', 'name', 'symbol', 'decimal_places']
    search_fields = ['code', 'name']


@admin.register(Country)
class CountryAdmin(admin.ModelAdmin):
    list_display = ['name', 'iso2', 'phone_code', 'currency', 'tax_name', 'tax_rate', 'payment_gateway', 'is_active']
    list_filter = ['is_active', 'payment_gateway', 'currency']
    search_fields = ['name', 'iso2']


@admin.register(City)
class CityAdmin(admin.ModelAdmin):
    list_display = ['name', 'state', 'country', 'is_active']
    list_filter = ['country', 'is_active']
    search_fields = ['name', 'state']
