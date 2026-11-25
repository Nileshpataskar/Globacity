from decimal import Decimal

from django.conf import settings
from django.db import models
from django.utils import timezone

from apps.core.models import BaseModel


def quantize(amount, currency):
    """Round to the currency's minor units (e.g. 2 for AED, 0 for JPY, 3 for KWD)."""
    return Decimal(amount).quantize(Decimal(1).scaleb(-currency.decimal_places))


class ChargeType(BaseModel):
    class Frequency(models.TextChoices):
        ONE_TIME = 'one_time'
        MONTHLY = 'monthly'
        QUARTERLY = 'quarterly'
        YEARLY = 'yearly'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='charge_types')
    name = models.CharField(max_length=100)
    default_amount = models.DecimalField(max_digits=12, decimal_places=3, default=0)
    frequency = models.CharField(max_length=20, choices=Frequency.choices, default=Frequency.MONTHLY)
    is_taxable = models.BooleanField(default=True, help_text="Apply the country's tax (VAT/GST)")
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


class Invoice(BaseModel):
    """A due raised against a unit. Currency and tax rate are snapshotted from the country at issue time."""

    class Status(models.TextChoices):
        UNPAID = 'unpaid'
        PARTIALLY_PAID = 'partially_paid'
        PAID = 'paid'
        CANCELLED = 'cancelled'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='invoices')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='invoices')
    charge_type = models.ForeignKey(ChargeType, on_delete=models.SET_NULL, null=True, blank=True)
    number = models.CharField(max_length=30, unique=True)
    title = models.CharField(max_length=150)
    period_label = models.CharField(max_length=60, blank=True, help_text='e.g. Q4 2026, October 2026')
    currency = models.ForeignKey('locations.Currency', on_delete=models.PROTECT)
    amount = models.DecimalField(max_digits=12, decimal_places=3)
    tax_name = models.CharField(max_length=20, blank=True)
    tax_rate = models.DecimalField(max_digits=5, decimal_places=2, default=0)
    tax_amount = models.DecimalField(max_digits=12, decimal_places=3, default=0)
    total = models.DecimalField(max_digits=12, decimal_places=3)
    paid_amount = models.DecimalField(max_digits=12, decimal_places=3, default=0)
    due_date = models.DateField()
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.UNPAID)
    issued_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['due_date', 'created_at']
        indexes = [models.Index(fields=['unit', 'status'])]

    def __str__(self):
        return f'{self.number} · {self.title}'

    @property
    def balance(self):
        return self.total - self.paid_amount

    @property
    def is_overdue(self):
        return self.status in (self.Status.UNPAID, self.Status.PARTIALLY_PAID) and self.due_date < timezone.localdate()


class Payment(BaseModel):
    class Method(models.TextChoices):
        CARD = 'card'
        APPLE_PAY = 'apple_pay'
        GOOGLE_PAY = 'google_pay'
        BANK_TRANSFER = 'bank_transfer'
        CASH = 'cash'
        CHEQUE = 'cheque'

    class Status(models.TextChoices):
        INITIATED = 'initiated'
        SUCCESS = 'success'
        FAILED = 'failed'
        CANCELLED = 'cancelled'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='payments')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='payments')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='payments')
    reference = models.CharField(max_length=40, unique=True)
    currency = models.ForeignKey('locations.Currency', on_delete=models.PROTECT)
    amount = models.DecimalField(max_digits=12, decimal_places=3)
    method = models.CharField(max_length=20, choices=Method.choices)
    gateway = models.CharField(max_length=20, help_text='mock, noqodi, offline, ...')
    gateway_reference = models.CharField(max_length=100, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.INITIATED)
    paid_at = models.DateTimeField(null=True, blank=True)
    raw_response = models.JSONField(default=dict, blank=True)
    invoices = models.ManyToManyField(Invoice, through='PaymentAllocation', related_name='payments')

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.reference


class PaymentAllocation(models.Model):
    payment = models.ForeignKey(Payment, on_delete=models.CASCADE, related_name='allocations')
    invoice = models.ForeignKey(Invoice, on_delete=models.CASCADE, related_name='allocations')
    amount = models.DecimalField(max_digits=12, decimal_places=3)

    class Meta:
        constraints = [models.UniqueConstraint(fields=['payment', 'invoice'], name='unique_allocation')]
