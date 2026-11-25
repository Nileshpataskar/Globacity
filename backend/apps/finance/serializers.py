from decimal import Decimal

from rest_framework import serializers

from apps.communities.models import Tower

from .models import ChargeType, Invoice, Payment, PaymentAllocation


class ChargeTypeSerializer(serializers.ModelSerializer):
    class Meta:
        model = ChargeType
        fields = ['id', 'community', 'name', 'default_amount', 'frequency', 'is_taxable', 'is_active', 'created_at']


class InvoiceSerializer(serializers.ModelSerializer):
    balance = serializers.DecimalField(max_digits=12, decimal_places=3, read_only=True)
    is_overdue = serializers.BooleanField(read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    currency_symbol = serializers.CharField(source='currency.symbol', read_only=True)

    class Meta:
        model = Invoice
        fields = ['id', 'number', 'title', 'period_label', 'unit', 'unit_label', 'currency', 'currency_symbol',
                  'amount', 'tax_name', 'tax_rate', 'tax_amount', 'total', 'paid_amount', 'balance', 'due_date',
                  'status', 'is_overdue', 'created_at']
        read_only_fields = fields


class InvoiceCreateSerializer(serializers.ModelSerializer):
    """Single invoice. Currency and tax are derived from the community's country."""

    taxable = serializers.BooleanField(required=False, help_text='Defaults to the charge type setting')

    class Meta:
        model = Invoice
        fields = ['unit', 'charge_type', 'title', 'period_label', 'amount', 'due_date', 'taxable']
        extra_kwargs = {'title': {'required': False}, 'amount': {'required': False}}

    def validate(self, attrs):
        ct = attrs.get('charge_type')
        if ct and ct.community_id != attrs['unit'].community.pk:
            raise serializers.ValidationError({'charge_type': 'Charge type belongs to another community.'})
        attrs.setdefault('title', ct.name if ct else '')
        if not attrs['title']:
            raise serializers.ValidationError({'title': 'Required when no charge_type is given.'})
        if 'amount' not in attrs:
            if not ct:
                raise serializers.ValidationError({'amount': 'Required when no charge_type is given.'})
            attrs['amount'] = ct.default_amount
        if attrs['amount'] <= 0:
            raise serializers.ValidationError({'amount': 'Must be greater than zero.'})
        return attrs


class BulkInvoiceSerializer(serializers.Serializer):
    community = serializers.UUIDField()
    charge_type = serializers.PrimaryKeyRelatedField(queryset=ChargeType.objects.all(), required=False)
    title = serializers.CharField(required=False)
    amount = serializers.DecimalField(max_digits=12, decimal_places=3, required=False)
    period_label = serializers.CharField(required=False, allow_blank=True, default='')
    due_date = serializers.DateField()
    taxable = serializers.BooleanField(required=False)
    tower = serializers.PrimaryKeyRelatedField(queryset=Tower.objects.all(), required=False,
                                               help_text='Limit to one tower')
    only_occupied = serializers.BooleanField(default=True, help_text='Only units with an approved resident')


class BulkInvoiceResultSerializer(serializers.Serializer):
    created = serializers.IntegerField()


class OfflinePaymentSerializer(serializers.Serializer):
    amount = serializers.DecimalField(max_digits=12, decimal_places=3, min_value=Decimal('0.001'))
    method = serializers.ChoiceField(choices=[Payment.Method.CASH, Payment.Method.CHEQUE, Payment.Method.BANK_TRANSFER])
    reference = serializers.CharField(required=False, allow_blank=True)


class AllocationSerializer(serializers.ModelSerializer):
    number = serializers.CharField(source='invoice.number')
    title = serializers.CharField(source='invoice.title')

    class Meta:
        model = PaymentAllocation
        fields = ['invoice', 'number', 'title', 'amount']


class PaymentSerializer(serializers.ModelSerializer):
    allocations = AllocationSerializer(many=True, read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    paid_by = serializers.CharField(source='user.full_name', read_only=True, default=None)

    class Meta:
        model = Payment
        fields = ['id', 'reference', 'unit', 'unit_label', 'paid_by', 'currency', 'amount', 'method', 'gateway',
                  'gateway_reference', 'status', 'paid_at', 'allocations', 'created_at']
        read_only_fields = fields


class CheckoutSerializer(serializers.Serializer):
    invoice_ids = serializers.ListField(child=serializers.UUIDField(), allow_empty=False)
    method = serializers.ChoiceField(choices=[Payment.Method.CARD, Payment.Method.APPLE_PAY,
                                              Payment.Method.GOOGLE_PAY, Payment.Method.BANK_TRANSFER])


class CheckoutResponseSerializer(serializers.Serializer):
    payment = PaymentSerializer()
    checkout = serializers.DictField()


class MockConfirmSerializer(serializers.Serializer):
    success = serializers.BooleanField(default=True)


class DuesSummarySerializer(serializers.Serializer):
    currency = serializers.CharField()
    currency_symbol = serializers.CharField()
    decimal_places = serializers.IntegerField()
    outstanding = serializers.DecimalField(max_digits=14, decimal_places=3)
    overdue = serializers.DecimalField(max_digits=14, decimal_places=3)
    pending_count = serializers.IntegerField()
    next_due_date = serializers.DateField(allow_null=True)


class StatementEntrySerializer(serializers.Serializer):
    date = serializers.DateField()
    description = serializers.CharField()
    reference = serializers.CharField()
    debit = serializers.DecimalField(max_digits=14, decimal_places=3)
    credit = serializers.DecimalField(max_digits=14, decimal_places=3)
    balance = serializers.DecimalField(max_digits=14, decimal_places=3)


class StatementSerializer(serializers.Serializer):
    currency = serializers.CharField()
    opening_balance = serializers.DecimalField(max_digits=14, decimal_places=3)
    closing_balance = serializers.DecimalField(max_digits=14, decimal_places=3)
    entries = StatementEntrySerializer(many=True)


class DefaulterSerializer(serializers.Serializer):
    unit = serializers.UUIDField()
    unit_label = serializers.CharField()
    residents = serializers.ListField(child=serializers.CharField())
    currency = serializers.CharField()
    overdue_amount = serializers.DecimalField(max_digits=14, decimal_places=3)
    overdue_invoices = serializers.IntegerField()
    oldest_due_date = serializers.DateField()
    days_overdue = serializers.IntegerField()


class RemindSerializer(serializers.Serializer):
    community = serializers.UUIDField()
    units = serializers.ListField(child=serializers.UUIDField(), required=False,
                                  help_text='Defaults to every defaulter in the community')
    message = serializers.CharField(required=False, allow_blank=True)


class RemindResultSerializer(serializers.Serializer):
    units_notified = serializers.IntegerField()
