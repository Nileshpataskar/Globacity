import secrets
from decimal import Decimal

from django.db import transaction
from django.utils import timezone

from apps.notifications.models import Notification
from apps.notifications.service import notify_unit

from .models import Invoice, Payment, quantize


def _unique(model, field, make, exclude=()):
    for _ in range(20):
        value = make()
        if value not in exclude and not model.objects.filter(**{field: value}).exists():
            return value
    raise RuntimeError('Could not generate a unique reference')


def new_invoice_number(exclude=()):
    return _unique(Invoice, 'number', lambda: f'INV-{timezone.now():%y%m}-{secrets.token_hex(3).upper()}', exclude)


def new_payment_reference():
    return _unique(Payment, 'reference', lambda: f'PAY-{timezone.now():%y%m%d}-{secrets.token_hex(4).upper()}')


def build_invoice(*, community, unit, title, amount, due_date, period_label='', charge_type=None, taxable=None,
                  issued_by=None, exclude_numbers=()):
    """Unsaved invoice with currency and tax taken from the community's country."""
    country = community.country
    currency = country.currency
    amount = quantize(amount, currency)
    taxable = charge_type.is_taxable if taxable is None and charge_type else bool(taxable)
    rate = country.tax_rate if taxable else Decimal('0')
    tax = quantize(amount * rate / 100, currency)
    return Invoice(
        community=community, unit=unit, charge_type=charge_type, number=new_invoice_number(exclude_numbers), title=title,
        period_label=period_label, currency=currency, amount=amount, tax_name=country.tax_name if taxable else '',
        tax_rate=rate, tax_amount=tax, total=amount + tax, due_date=due_date, issued_by=issued_by,
    )


def apply_payment_to_invoices(payment):
    for alloc in payment.allocations.select_related('invoice').select_for_update():
        inv = alloc.invoice
        inv.paid_amount = min(inv.total, inv.paid_amount + alloc.amount)
        inv.status = Invoice.Status.PAID if inv.paid_amount >= inv.total else Invoice.Status.PARTIALLY_PAID
        inv.save(update_fields=['paid_amount', 'status', 'updated_at'])


@transaction.atomic
def complete_payment(payment, success, gateway_reference='', raw=None):
    payment = Payment.objects.select_for_update().get(pk=payment.pk)
    if payment.status != Payment.Status.INITIATED:
        return payment
    payment.gateway_reference = gateway_reference or payment.gateway_reference
    payment.raw_response = raw or payment.raw_response
    if success:
        payment.status = Payment.Status.SUCCESS
        payment.paid_at = timezone.now()
        payment.save()
        apply_payment_to_invoices(payment)
        transaction.on_commit(lambda: notify_unit(
            payment.unit, 'Payment received', f'{payment.currency_id} {payment.amount} · {payment.reference}',
            Notification.Category.PAYMENT, {'payment_id': payment.id}, pref='payment_reminders',
        ))
    else:
        payment.status = Payment.Status.FAILED
        payment.save()
    return payment
