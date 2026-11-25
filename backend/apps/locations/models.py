from decimal import Decimal

from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from apps.core.models import BaseModel


class Currency(models.Model):
    """ISO-4217 currency. Shared by countries (e.g. EUR)."""

    code = models.CharField(max_length=3, primary_key=True, help_text='ISO-4217 code, e.g. AED, INR, USD')
    name = models.CharField(max_length=64)
    symbol = models.CharField(max_length=8)
    decimal_places = models.PositiveSmallIntegerField(default=2)

    class Meta:
        verbose_name_plural = 'currencies'
        ordering = ['code']

    def __str__(self):
        return self.code


class PaymentGateway(models.TextChoices):
    MOCK = 'mock', 'Mock (free, for development)'
    NOQODI = 'noqodi', 'Noqodi'
    RAZORPAY = 'razorpay', 'Razorpay'
    STRIPE = 'stripe', 'Stripe'


class Country(BaseModel):
    """Everything locale-specific lives here; communities inherit it."""

    name = models.CharField(max_length=100, unique=True)
    iso2 = models.CharField(max_length=2, unique=True, help_text='ISO-3166 alpha-2, e.g. AE')
    phone_code = models.CharField(max_length=6, help_text='Dialing code including +, e.g. +971')
    phone_number_length = models.PositiveSmallIntegerField(default=9, help_text='Digits after the dialing code')
    currency = models.ForeignKey(Currency, on_delete=models.PROTECT, related_name='countries')
    timezone = models.CharField(max_length=64, default='UTC', help_text='IANA name, e.g. Asia/Dubai')
    default_language = models.CharField(max_length=8, default='en')
    supported_languages = models.JSONField(default=list, blank=True, help_text='e.g. ["en", "ar"]')
    date_format = models.CharField(max_length=20, default='dd/MM/yyyy')
    tax_name = models.CharField(max_length=20, default='VAT', help_text='VAT, GST, ...')
    tax_rate = models.DecimalField(
        max_digits=5, decimal_places=2, default=Decimal('0'),
        validators=[MinValueValidator(Decimal('0')), MaxValueValidator(Decimal('100'))],
        help_text='Percent applied to taxable charges',
    )
    payment_gateway = models.CharField(max_length=20, choices=PaymentGateway.choices, default=PaymentGateway.MOCK)
    emergency_numbers = models.JSONField(
        default=dict, blank=True, help_text='e.g. {"police": "999", "ambulance": "998", "fire": "997"}'
    )
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name_plural = 'countries'
        ordering = ['name']

    def __str__(self):
        return self.name


class City(BaseModel):
    country = models.ForeignKey(Country, on_delete=models.PROTECT, related_name='cities')
    name = models.CharField(max_length=100)
    state = models.CharField(max_length=100, blank=True, help_text='State / emirate / province')
    timezone = models.CharField(max_length=64, blank=True, help_text='Overrides the country timezone if set')
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name_plural = 'cities'
        ordering = ['name']
        constraints = [models.UniqueConstraint(fields=['country', 'name'], name='unique_city_per_country')]

    def __str__(self):
        return f'{self.name}, {self.country.iso2}'

    @property
    def effective_timezone(self):
        return self.timezone or self.country.timezone
