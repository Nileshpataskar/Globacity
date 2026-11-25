from django.contrib import admin

from .models import ChargeType, Invoice, Payment, PaymentAllocation


@admin.register(ChargeType)
class ChargeTypeAdmin(admin.ModelAdmin):
    list_display = ['name', 'community', 'default_amount', 'frequency', 'is_taxable', 'is_active']
    list_filter = ['community', 'frequency']


@admin.register(Invoice)
class InvoiceAdmin(admin.ModelAdmin):
    list_display = ['number', 'title', 'unit', 'currency', 'total', 'paid_amount', 'due_date', 'status']
    list_filter = ['status', 'community', 'currency']
    search_fields = ['number', 'title', 'unit__number']
    raw_id_fields = ['unit', 'issued_by']


class AllocationInline(admin.TabularInline):
    model = PaymentAllocation
    extra = 0
    raw_id_fields = ['invoice']


@admin.register(Payment)
class PaymentAdmin(admin.ModelAdmin):
    list_display = ['reference', 'unit', 'currency', 'amount', 'method', 'gateway', 'status', 'paid_at']
    list_filter = ['status', 'gateway', 'method', 'community']
    search_fields = ['reference', 'gateway_reference']
    raw_id_fields = ['unit', 'user']
    inlines = [AllocationInline]
