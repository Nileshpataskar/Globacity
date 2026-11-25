from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal

from django.db import transaction
from django.db.models import Sum
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import permissions, status
from rest_framework.decorators import action
from rest_framework.exceptions import APIException, NotFound, PermissionDenied, ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.communities.models import Community, Membership, Unit
from apps.core.permissions import has_community_role, manager_scope
from apps.core.scoping import ManageReadOnlyViewSet, ManageViewSet, UnitScopedMixin, UnitScopedReadOnlyViewSet
from apps.notifications.models import Notification
from apps.notifications.service import notify_unit

from .gateways import GatewayNotConfigured, get_gateway
from .models import ChargeType, Invoice, Payment, PaymentAllocation, quantize
from .serializers import (
    BulkInvoiceResultSerializer,
    BulkInvoiceSerializer,
    ChargeTypeSerializer,
    CheckoutResponseSerializer,
    CheckoutSerializer,
    DefaulterSerializer,
    DuesSummarySerializer,
    InvoiceCreateSerializer,
    InvoiceSerializer,
    MockConfirmSerializer,
    OfflinePaymentSerializer,
    PaymentSerializer,
    RemindResultSerializer,
    RemindSerializer,
    StatementSerializer,
)
from .services import build_invoice, complete_payment, new_payment_reference

OPEN = [Invoice.Status.UNPAID, Invoice.Status.PARTIALLY_PAID]


class ServiceUnavailable(APIException):
    status_code = 503
    default_detail = 'Payment gateway unavailable.'


# ---------------------------------------------------------------------------
# Residents
# ---------------------------------------------------------------------------


class InvoiceViewSet(UnitScopedReadOnlyViewSet):
    """All invoices for your unit. ``?open=true`` returns only what's still due."""

    serializer_class = InvoiceSerializer
    queryset = Invoice.objects.select_related('unit__tower', 'currency')
    filterset_fields = ['status']
    ordering_fields = ['due_date', 'created_at', 'total']

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.query_params.get('open') == 'true':
            qs = qs.filter(status__in=OPEN)
        return qs

    @extend_schema(parameters=[OpenApiParameter('open', bool)])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    @extend_schema(responses=DuesSummarySerializer)
    @action(detail=False, methods=['get'])
    def summary(self, request):
        currency = self.community.currency
        open_qs = Invoice.objects.filter(unit=self.unit, status__in=OPEN)
        totals = open_qs.aggregate(total=Sum('total'), paid=Sum('paid_amount'))
        overdue = open_qs.filter(due_date__lt=timezone.localdate()).aggregate(total=Sum('total'), paid=Sum('paid_amount'))
        nxt = open_qs.order_by('due_date').first()
        return Response(DuesSummarySerializer({
            'currency': currency.code, 'currency_symbol': currency.symbol, 'decimal_places': currency.decimal_places,
            'outstanding': (totals['total'] or 0) - (totals['paid'] or 0),
            'overdue': (overdue['total'] or 0) - (overdue['paid'] or 0),
            'pending_count': open_qs.count(), 'next_due_date': nxt.due_date if nxt else None,
        }).data)

    @extend_schema(parameters=[OpenApiParameter('from', date), OpenApiParameter('to', date)],
                   responses=StatementSerializer)
    @action(detail=False, methods=['get'])
    def statement(self, request):
        """Statement of account: invoices (debits) and successful payments (credits) with a running balance."""
        try:
            start = date.fromisoformat(request.query_params['from']) if 'from' in request.query_params else None
            end = date.fromisoformat(request.query_params['to']) if 'to' in request.query_params else None
        except ValueError:
            raise ValidationError({'from': 'Use YYYY-MM-DD.'})
        rows = [(i.created_at.date(), f'{i.title} {i.period_label}'.strip(), i.number, i.total, Decimal('0'))
                for i in Invoice.objects.filter(unit=self.unit).exclude(status=Invoice.Status.CANCELLED)]
        rows += [(p.paid_at.date(), f'Payment · {p.get_method_display()}', p.reference, Decimal('0'), p.amount)
                 for p in Payment.objects.filter(unit=self.unit, status=Payment.Status.SUCCESS)]
        rows.sort(key=lambda r: (r[0], r[4] > 0))
        opening, balance, entries = Decimal('0'), Decimal('0'), []
        for d, desc, ref, debit, credit in rows:
            if end and d > end:
                break
            balance += debit - credit
            if start and d < start:
                opening = balance
                continue
            entries.append({'date': d, 'description': desc, 'reference': ref, 'debit': debit, 'credit': credit,
                            'balance': balance})
        return Response(StatementSerializer({
            'currency': self.community.currency.code, 'opening_balance': opening, 'closing_balance': balance,
            'entries': entries,
        }).data)


class PaymentViewSet(UnitScopedReadOnlyViewSet):
    """Payment history and checkout."""

    serializer_class = PaymentSerializer
    queryset = Payment.objects.select_related('unit__tower', 'user').prefetch_related('allocations__invoice')
    tower_lookup = 'unit__tower'
    filterset_fields = ['status', 'method']

    @extend_schema(request=CheckoutSerializer, responses={201: CheckoutResponseSerializer})
    @action(detail=False, methods=['post'])
    def checkout(self, request):
        """Start paying one or more invoices. Uses the gateway configured for the community's country."""
        s = CheckoutSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        ids = set(s.validated_data['invoice_ids'])
        invoices = list(Invoice.objects.filter(pk__in=ids, unit=self.unit, status__in=OPEN))
        if len(invoices) != len(ids):
            raise ValidationError({'invoice_ids': 'Some invoices are not payable for this unit.'})
        currencies = {i.currency_id for i in invoices}
        if len(currencies) > 1:
            raise ValidationError({'invoice_ids': 'Invoices must share one currency.'})
        country = self.community.country
        try:
            gateway = get_gateway(country.payment_gateway)
        except GatewayNotConfigured as e:
            raise ServiceUnavailable(str(e))
        currency = invoices[0].currency
        with transaction.atomic():
            payment = Payment.objects.create(
                community=self.community, unit=self.unit, user=request.user, reference=new_payment_reference(),
                currency=currency, amount=quantize(sum(i.balance for i in invoices), currency),
                method=s.validated_data['method'], gateway=gateway.code,
            )
            PaymentAllocation.objects.bulk_create(
                [PaymentAllocation(payment=payment, invoice=i, amount=i.balance) for i in invoices]
            )
        try:
            checkout = gateway.create_checkout(payment, request)
        except GatewayNotConfigured as e:
            payment.status = Payment.Status.CANCELLED
            payment.save(update_fields=['status'])
            raise ServiceUnavailable(str(e))
        return Response({'payment': PaymentSerializer(payment).data, 'checkout': checkout},
                        status=status.HTTP_201_CREATED)

    @extend_schema(request=MockConfirmSerializer, responses=PaymentSerializer)
    @action(detail=True, methods=['post'], url_path='mock-confirm', url_name='mock-confirm')
    def mock_confirm(self, request, pk=None):
        """Development only: complete a payment made through the mock gateway."""
        payment = self.get_object()
        if payment.gateway != 'mock':
            raise NotFound()
        s = MockConfirmSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        payment = complete_payment(payment, s.validated_data['success'], gateway_reference=f'MOCK-{payment.reference}')
        return Response(PaymentSerializer(payment).data)


class PaymentWebhookView(APIView):
    """Server-to-server callback from the payment gateway."""

    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    @extend_schema(request=None, responses=PaymentSerializer, tags=['Finance'])
    def post(self, request, gateway):
        try:
            reference, success, gateway_ref, raw = get_gateway(gateway).parse_webhook(request)
        except GatewayNotConfigured as e:
            raise ServiceUnavailable(str(e))
        payment = Payment.objects.filter(reference=reference, gateway=gateway).first()
        if payment is None:
            raise NotFound('Unknown payment reference.')
        return Response(PaymentSerializer(complete_payment(payment, success, gateway_ref, raw)).data)


# ---------------------------------------------------------------------------
# Management
# ---------------------------------------------------------------------------


class ManageChargeTypeViewSet(ManageViewSet):
    readable_by_tower_admins = True
    serializer_class = ChargeTypeSerializer
    queryset = ChargeType.objects.all()
    filterset_fields = ['community', 'is_active', 'frequency']


class ManageInvoiceViewSet(ManageViewSet):
    queryset = Invoice.objects.select_related('unit__tower', 'currency')
    tower_lookup = 'unit__tower'
    filterset_fields = {'status': ['exact'], 'unit': ['exact'], 'unit__tower': ['exact'], 'due_date': ['gte', 'lte'],
                        'community': ['exact'], 'charge_type': ['exact']}
    search_fields = ['number', 'title', 'unit__number']
    http_method_names = ['get', 'post']

    def get_serializer_class(self):
        return InvoiceCreateSerializer if self.action == 'create' else InvoiceSerializer

    @extend_schema(request=InvoiceCreateSerializer, responses={201: InvoiceSerializer})
    def create(self, request, *args, **kwargs):
        s = InvoiceCreateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        community = d['unit'].community
        self.assert_can_manage(community, d['unit'].tower)
        invoice = build_invoice(community=community, unit=d['unit'], title=d['title'], amount=d['amount'],
                                due_date=d['due_date'], period_label=d.get('period_label', ''),
                                charge_type=d.get('charge_type'), taxable=d.get('taxable'), issued_by=request.user)
        invoice.save()
        notify_unit(invoice.unit, 'New invoice', f'{invoice.title} · {invoice.currency_id} {invoice.total}',
                    Notification.Category.PAYMENT, {'invoice_id': invoice.id}, pref='payment_reminders')
        return Response(InvoiceSerializer(invoice).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=BulkInvoiceSerializer, responses=BulkInvoiceResultSerializer)
    @action(detail=False, methods=['post'])
    def bulk(self, request):
        """Raise the same charge for every unit in a community (or one tower)."""
        s = BulkInvoiceSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        community = Community.objects.select_related('city__country__currency').filter(pk=d['community']).first()
        if community is None:
            raise ValidationError({'community': 'Not found.'})
        if not has_community_role(request.user, community, self.roles):
            raise PermissionDenied('You do not manage this community.')
        full, my_towers = manager_scope(request.user, self.roles)
        whole_community = full is None or community.pk in full
        if d.get('tower') and not whole_community and d['tower'].pk not in my_towers:
            raise PermissionDenied('You only manage some towers of this community.')
        ct = d.get('charge_type')
        if ct and ct.community_id != community.pk:
            raise ValidationError({'charge_type': 'Charge type belongs to another community.'})
        title = d.get('title') or (ct.name if ct else None) or 'Maintenance'
        units = Unit.objects.filter(tower__community=community).select_related('tower')
        if d.get('tower'):
            units = units.filter(tower=d['tower'])
        elif not whole_community:
            units = units.filter(tower__in=my_towers)
        if d['only_occupied']:
            units = units.filter(memberships__status=Membership.Status.APPROVED).distinct()

        def amount_for(unit):
            # Explicit amount > the tower's own maintenance amount > the charge type default.
            if d.get('amount') is not None:
                return d['amount']
            if unit.tower.maintenance_amount is not None:
                return unit.tower.maintenance_amount
            return ct.default_amount if ct else None

        missing = sorted({u.tower.name for u in units if amount_for(u) is None})
        if missing:
            raise ValidationError({'amount': f"Enter an amount, or set a maintenance amount for: {', '.join(missing)}."})
        invoices, numbers = [], set()
        for u in units:
            inv = build_invoice(community=community, unit=u, title=title, amount=amount_for(u), due_date=d['due_date'],
                                period_label=d['period_label'], charge_type=ct, taxable=d.get('taxable'),
                                issued_by=request.user, exclude_numbers=numbers)
            numbers.add(inv.number)
            invoices.append(inv)
        Invoice.objects.bulk_create(invoices)
        for inv in invoices:
            notify_unit(inv.unit, 'New invoice', f'{inv.title} · {inv.currency_id} {inv.total}',
                        Notification.Category.PAYMENT, {'invoice_id': inv.id}, pref='payment_reminders')
        return Response({'created': len(invoices)})

    @extend_schema(request=None, responses=InvoiceSerializer)
    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        inv = self.get_object()
        if inv.paid_amount > 0:
            raise ValidationError({'detail': 'Invoices with payments cannot be cancelled.'})
        inv.status = Invoice.Status.CANCELLED
        inv.save(update_fields=['status'])
        return Response(InvoiceSerializer(inv).data)

    @extend_schema(request=OfflinePaymentSerializer, responses=PaymentSerializer)
    @action(detail=True, methods=['post'], url_path='record-payment')
    def record_payment(self, request, pk=None):
        """Record cash / cheque / bank transfer received at the office."""
        inv = self.get_object()
        if inv.status not in OPEN:
            raise ValidationError({'detail': 'Invoice is not open.'})
        s = OfflinePaymentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        amount = quantize(min(s.validated_data['amount'], inv.balance), inv.currency)
        with transaction.atomic():
            payment = Payment.objects.create(
                community=inv.community, unit=inv.unit, user=request.user, reference=new_payment_reference(),
                currency=inv.currency, amount=amount, method=s.validated_data['method'], gateway='offline',
                gateway_reference=s.validated_data.get('reference', ''),
            )
            PaymentAllocation.objects.create(payment=payment, invoice=inv, amount=amount)
        payment = complete_payment(payment, True)
        return Response(PaymentSerializer(payment).data, status=status.HTTP_201_CREATED)


class ManagePaymentViewSet(ManageReadOnlyViewSet):
    serializer_class = PaymentSerializer
    queryset = Payment.objects.select_related('unit__tower', 'user').prefetch_related('allocations__invoice')
    filterset_fields = {'status': ['exact'], 'method': ['exact'], 'unit': ['exact'], 'community': ['exact'],
                        'paid_at': ['gte', 'lte']}
    search_fields = ['reference', 'gateway_reference', 'unit__number']


def defaulters_for(invoices):
    today = timezone.localdate()
    grouped = defaultdict(list)
    for inv in invoices:
        grouped[inv.unit].append(inv)
    rows = []
    for unit, invs in grouped.items():
        residents = [m.user.full_name or m.user.phone for m in unit.memberships.all()
                     if m.status == Membership.Status.APPROVED]
        oldest = min(i.due_date for i in invs)
        rows.append({
            'unit': unit.pk, 'unit_label': unit.label, 'residents': residents, 'currency': invs[0].currency_id,
            'overdue_amount': sum(i.balance for i in invs), 'overdue_invoices': len(invs),
            'oldest_due_date': oldest, 'days_overdue': (today - oldest).days,
        })
    return sorted(rows, key=lambda r: r['overdue_amount'], reverse=True)


class ManageDefaulterViewSet(ManageReadOnlyViewSet):
    """Units with overdue invoices, highest amount first."""

    serializer_class = DefaulterSerializer
    queryset = Invoice.objects.select_related('unit__tower').prefetch_related('unit__memberships__user')
    tower_lookup = 'unit__tower'
    pagination_class = None

    def overdue(self):
        qs = self.get_queryset().filter(status__in=OPEN, due_date__lt=timezone.localdate())
        min_days = self.request.query_params.get('min_days')
        if min_days and min_days.isdigit():
            qs = qs.filter(due_date__lte=timezone.localdate() - timedelta(days=int(min_days)))
        return qs

    @extend_schema(parameters=[OpenApiParameter('community', str), OpenApiParameter('min_days', int)],
                   responses=DefaulterSerializer(many=True))
    def list(self, request, *args, **kwargs):
        return Response(DefaulterSerializer(defaulters_for(self.overdue()), many=True).data)

    def retrieve(self, request, *args, **kwargs):
        raise NotFound()

    @extend_schema(request=RemindSerializer, responses=RemindResultSerializer)
    @action(detail=False, methods=['post'])
    def remind(self, request):
        """Send payment reminders (in-app + push) to defaulting units."""
        s = RemindSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        community = Community.objects.filter(pk=s.validated_data['community']).first()
        if community is None:
            raise ValidationError({'community': 'Not found.'})
        if not has_community_role(request.user, community, self.roles):
            raise PermissionDenied('You do not manage this community.')
        qs = self.overdue().filter(community=community)  # already limited to the caller's towers
        if s.validated_data.get('units'):
            qs = qs.filter(unit__in=s.validated_data['units'])
        rows = defaulters_for(qs)
        units = {u.pk: u for u in Unit.objects.filter(pk__in=[r['unit'] for r in rows])}
        for r in rows:
            body = s.validated_data.get('message') or (
                f"You have {r['overdue_invoices']} overdue invoice(s) totalling {r['currency']} {r['overdue_amount']}. "
                'Please pay at the earliest to avoid service restrictions.'
            )
            notify_unit(units[r['unit']], 'Payment reminder', body, Notification.Category.PAYMENT,
                        {'unit_id': r['unit']})
        return Response({'units_notified': len(rows)})
