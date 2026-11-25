from django.db.models import Q, Sum
from drf_spectacular.utils import OpenApiParameter, extend_schema, inline_serializer
from rest_framework import permissions, serializers
from rest_framework.response import Response
from rest_framework.views import APIView

from .scoping import UnitScopedMixin


class HealthView(APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []

    @extend_schema(responses=inline_serializer('Health', {'status': serializers.CharField()}), tags=['General'])
    def get(self, request):
        return Response({'status': 'ok'})


class CurrencyInfoSerializer(serializers.Serializer):
    code = serializers.CharField()
    symbol = serializers.CharField()
    decimal_places = serializers.IntegerField()


class CountryContextSerializer(serializers.Serializer):
    name = serializers.CharField()
    iso2 = serializers.CharField()
    phone_code = serializers.CharField()
    phone_number_length = serializers.IntegerField()
    currency = CurrencyInfoSerializer()
    tax_name = serializers.CharField()
    tax_rate = serializers.DecimalField(max_digits=5, decimal_places=2)
    timezone = serializers.CharField()
    default_language = serializers.CharField()
    supported_languages = serializers.ListField(child=serializers.CharField())
    date_format = serializers.CharField()
    payment_gateway = serializers.CharField()


class ContextSerializer(serializers.Serializer):
    membership = serializers.DictField()
    unit = serializers.DictField()
    community = serializers.DictField()
    country = CountryContextSerializer()
    staff_roles = serializers.ListField(child=serializers.CharField())
    counts = serializers.DictField()


class ContextView(UnitScopedMixin, APIView):
    """Everything the app needs to render the selected unit: branding, currency, tax, timezone, languages, badges.

    Call it on launch and whenever the user switches property.
    """

    @extend_schema(responses=ContextSerializer, tags=['Me'])
    def get(self, request):
        from apps.communities.models import StaffMember
        from apps.finance.models import Invoice
        from apps.gate.models import Visitor
        from apps.notifications.models import Notification

        m = self.membership
        unit, community = m.unit, self.community
        country = community.country
        currency = country.currency
        open_dues = Invoice.objects.filter(unit=unit, status__in=['unpaid', 'partially_paid']).aggregate(
            total=Sum('total'), paid=Sum('paid_amount'))
        data = {
            'membership': {'id': str(m.id), 'role': m.role, 'status': m.status},
            'unit': {'id': str(unit.id), 'number': unit.number, 'floor': unit.floor, 'tower': unit.tower.name,
                     'tower_id': str(unit.tower_id), 'label': unit.label, 'unit_type': unit.unit_type},
            'community': {
                'id': str(community.id), 'name': community.name, 'address': community.address,
                'city': community.city.name, 'logo': request.build_absolute_uri(community.logo.url) if community.logo else None,
                'primary_color': community.primary_color, 'secondary_color': community.secondary_color,
                'timezone': community.effective_timezone, 'contact_phone': community.contact_phone,
                'contact_email': community.contact_email, 'settings': community.settings,
            },
            'country': {
                'name': country.name, 'iso2': country.iso2, 'phone_code': country.phone_code,
                'phone_number_length': country.phone_number_length,
                'currency': {'code': currency.code, 'symbol': currency.symbol,
                             'decimal_places': currency.decimal_places},
                'tax_name': country.tax_name, 'tax_rate': country.tax_rate, 'timezone': country.timezone,
                'default_language': country.default_language,
                'supported_languages': country.supported_languages or [country.default_language],
                'date_format': country.date_format, 'payment_gateway': country.payment_gateway,
            },
            'staff_roles': list(StaffMember.objects.filter(user=request.user, community=community, is_active=True)
                                .values_list('role', flat=True)),
            'counts': {
                'visitors_waiting': Visitor.objects.filter(unit=unit, status=Visitor.Status.WAITING).count(),
                'unread_notifications': Notification.objects.filter(user=request.user, is_read=False).count(),
                'outstanding_dues': str((open_dues['total'] or 0) - (open_dues['paid'] or 0)),
            },
        }
        return Response(ContextSerializer(data).data)


class MyRolesView(APIView):
    """Staff roles across communities (for admin / guard apps) and platform-admin flag."""

    @extend_schema(responses=inline_serializer('MyRoles', {
        'is_platform_admin': serializers.BooleanField(),
        'roles': serializers.ListField(child=serializers.DictField()),
    }), tags=['Me'])
    def get(self, request):
        from apps.communities.models import StaffMember

        roles = (StaffMember.objects.filter(user=request.user, is_active=True).select_related('community')
                 .prefetch_related('towers'))
        return Response({
            'is_platform_admin': request.user.is_staff,
            'roles': [{'community_id': str(r.community_id), 'community': r.community.name, 'role': r.role,
                       'designation': r.designation, 'towers': [{'id': str(t.id), 'name': t.name} for t in r.towers.all()]}
                      for r in roles],
        })


class SearchResultSerializer(serializers.Serializer):
    type = serializers.ChoiceField(choices=['resident', 'staff', 'daily_help', 'visitor', 'notice', 'ticket',
                                            'classified'])
    id = serializers.CharField()
    title = serializers.CharField()
    subtitle = serializers.CharField(allow_blank=True)


class SearchView(UnitScopedMixin, APIView):
    """Universal search across people, notices, visitors, daily help, tickets and classifieds."""

    PER_TYPE = 5

    @extend_schema(parameters=[OpenApiParameter('q', str, required=True)],
                   responses=SearchResultSerializer(many=True), tags=['Search'])
    def get(self, request):
        from apps.accounts.models import UserSettings
        from apps.communities.models import Membership, StaffMember
        from apps.engagement.models import Classified, Notice
        from apps.gate.models import Visitor
        from apps.helpdesk.models import Ticket
        from apps.household.models import DailyHelp

        q = request.query_params.get('q', '').strip()
        if len(q) < 2:
            return Response([])
        unit, community, n = self.unit, self.community, self.PER_TYPE
        results = []

        hidden = set(UserSettings.objects.filter(privacy_prefs__show_in_directory=False).values_list('user_id', flat=True))
        for m in (Membership.objects.filter(unit__tower__community=community, status='approved')
                  .filter(Q(user__full_name__icontains=q) | Q(unit__number__icontains=q))
                  .exclude(user_id__in=hidden).select_related('user', 'unit__tower')[:n]):
            results.append(('resident', m.user_id, m.user.full_name, m.unit.label))
        for s in StaffMember.objects.filter(community=community, show_in_directory=True, is_active=True).filter(
                Q(name__icontains=q) | Q(designation__icontains=q))[:n]:
            results.append(('staff', s.id, s.name, s.designation or s.get_role_display()))
        for h in DailyHelp.objects.filter(assignments__unit=unit).filter(Q(name__icontains=q) | Q(role__icontains=q))[:n]:
            results.append(('daily_help', h.id, h.name, h.role))
        for v in Visitor.objects.filter(unit=unit).filter(Q(name__icontains=q) | Q(company__icontains=q))[:n]:
            results.append(('visitor', v.id, v.name, v.get_status_display()))
        for nt in Notice.objects.filter(community=community).filter(Q(title__icontains=q) | Q(body__icontains=q))[:n]:
            results.append(('notice', nt.id, nt.title, nt.category))
        for t in Ticket.objects.filter(unit=unit).filter(Q(title__icontains=q) | Q(number__icontains=q))[:n]:
            results.append(('ticket', t.id, f'{t.number} · {t.title}', t.get_status_display()))
        for c in Classified.objects.filter(community=community, status='active', title__icontains=q)[:n]:
            results.append(('classified', c.id, c.title, f'{c.currency_id} {c.price}'))

        rows = [{'type': t, 'id': str(i), 'title': title, 'subtitle': sub or ''} for t, i, title, sub in results]
        return Response(SearchResultSerializer(rows, many=True).data)


class ManageSummaryView(APIView):
    """Numbers for the management dashboard, limited to the caller's towers for tower admins."""

    permission_classes = [permissions.IsAuthenticated]

    @extend_schema(parameters=[OpenApiParameter('community', str, required=True)], responses=inline_serializer(
        'ManageSummary', {'counts': serializers.DictField(), 'money': serializers.DictField(),
                          'towers': serializers.ListField(child=serializers.DictField())}), tags=['Manage'])
    def get(self, request):
        from django.db.models import Count
        from django.utils import timezone
        from rest_framework.exceptions import PermissionDenied, ValidationError

        from apps.communities.models import Community, Membership, Unit
        from apps.engagement.models import MoveRequest
        from apps.finance.models import Invoice, Payment
        from apps.gate.models import Incident, SOSAlert, Visitor
        from apps.helpdesk.models import Ticket

        from .permissions import MANAGER_ROLES, has_community_role, manager_scope
        from .scoping import parse_uuid
        from .utils import community_today

        cid = request.query_params.get('community')
        if not cid:
            raise ValidationError({'community': 'This field is required.'})
        community = Community.objects.select_related('city__country__currency').filter(
            pk=parse_uuid(cid, 'community')).first()
        if community is None or not has_community_role(request.user, community, MANAGER_ROLES):
            raise PermissionDenied('You do not manage this community.')
        full, my_towers = manager_scope(request.user)
        whole = full is None or community.pk in full
        towers = community.towers.all() if whole else community.towers.filter(pk__in=my_towers)

        today = community_today(community)
        month_start = today.replace(day=1)
        units = Unit.objects.filter(tower__in=towers)
        members = Membership.objects.filter(unit__in=units)
        invoices = Invoice.objects.filter(unit__in=units)
        open_inv = invoices.filter(status__in=[Invoice.Status.UNPAID, Invoice.Status.PARTIALLY_PAID])
        overdue = open_inv.filter(due_date__lt=today)
        approved = Membership.Status.APPROVED

        def outstanding(qs):
            agg = qs.aggregate(t=Sum('total'), p=Sum('paid_amount'))
            return (agg['t'] or 0) - (agg['p'] or 0)

        per_tower = []
        for t in towers.annotate(n_units=Count('units', distinct=True)).order_by('name'):
            t_units = units.filter(tower=t)
            per_tower.append({
                'id': str(t.id), 'name': t.name, 'approval_mode': t.approval_mode,
                'maintenance_amount': None if t.maintenance_amount is None else str(t.maintenance_amount),
                'units': t.n_units,
                'occupied_units': t_units.filter(memberships__status=approved).distinct().count(),
                'residents': members.filter(unit__tower=t, status=approved).values('user').distinct().count(),
                'pending_approvals': members.filter(unit__tower=t, status=Membership.Status.PENDING).count(),
                'open_tickets': Ticket.objects.filter(unit__tower=t).exclude(status__in=['resolved', 'closed']).count(),
                'overdue': str(outstanding(overdue.filter(unit__tower=t))),
                'admins': list(t.staff.filter(is_active=True, role__in=MANAGER_ROLES).values_list('name', flat=True)),
            })

        collected = Payment.objects.filter(unit__in=units, status='success',
                                           paid_at__date__gte=month_start).aggregate(s=Sum('amount'))['s'] or 0
        return Response({
            'community': {'id': str(community.id), 'name': community.name,
                          'currency': community.currency.code, 'decimals': community.currency.decimal_places},
            'scope': 'community' if whole else 'towers',
            'counts': {
                'towers': len(per_tower),
                'units': units.count(),
                'occupied_units': units.filter(memberships__status=approved).distinct().count(),
                'residents': members.filter(status=approved).values('user').distinct().count(),
                'pending_approvals': members.filter(status=Membership.Status.PENDING).count(),
                'open_tickets': Ticket.objects.filter(unit__in=units).exclude(status__in=['resolved', 'closed']).count(),
                'pending_move_requests': MoveRequest.objects.filter(unit__in=units, status='pending').count(),
                'active_sos': SOSAlert.objects.filter(unit__in=units, status__in=['active', 'acknowledged']).count(),
                'open_incidents': Incident.objects.filter(community=community).exclude(status='resolved').count()
                if whole else Incident.objects.filter(unit__in=units).exclude(status='resolved').count(),
                'visitors_today': Visitor.objects.filter(unit__in=units, created_at__date=today).count(),
                'inside_now': Visitor.objects.filter(unit__in=units, status='inside').count(),
                'defaulter_units': overdue.values('unit').distinct().count(),
                'staff': community.staff.filter(is_active=True).count() if whole else 0,
            },
            'money': {
                'outstanding': str(outstanding(open_inv)),
                'overdue': str(outstanding(overdue)),
                'collected_this_month': str(collected),
                'invoiced_this_month': str(invoices.filter(created_at__date__gte=month_start).exclude(
                    status='cancelled').aggregate(s=Sum('total'))['s'] or 0),
            },
            'towers': per_tower,
        })
