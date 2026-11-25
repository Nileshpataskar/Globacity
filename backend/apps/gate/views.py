from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, serializers
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.response import Response

from apps.communities.models import Gate
from apps.core.permissions import GUARD_ROLES, MANAGER_ROLES, community_ids_for
from apps.core.scoping import GuardViewSet, ManageReadOnlyViewSet, UnitScopedCreateListViewSet, UnitScopedViewSet
from apps.core.utils import community_today
from apps.household.models import DailyHelp, DailyHelpAttendance
from apps.household.serializers import DailyHelpSerializer
from apps.household.views import helpers_queryset
from apps.notifications.models import Notification
from apps.notifications.service import notify_community_staff, notify_unit

from .models import FrequentEntry, KidExitPermission, SOSAlert, Visitor
from .serializers import (
    CodeLookupSerializer,
    CodeSerializer,
    FrequentEntrySerializer,
    KidExitSerializer,
    PreApproveSerializer,
    SOSAlertSerializer,
    VisitorSerializer,
    WalkInSerializer,
)
from .services import expire_stale_visitors, new_pass_code, resolve_code

S = Visitor.Status
BUCKETS = {
    'upcoming': [S.EXPECTED, S.WAITING],
    'inside': [S.INSIDE],
    'history': [S.EXITED, S.DENIED, S.LEFT_AT_GATE, S.CANCELLED, S.EXPIRED],
}
CAT = Notification.Category


def _transition(visitor, allowed_from, to, user, **extra):
    if visitor.status not in allowed_from:
        raise ValidationError({'status': f'Not possible while the visitor is "{visitor.get_status_display()}".'})
    visitor.status = to
    for k, v in extra.items():
        setattr(visitor, k, v)
    visitor.save()
    return visitor


# ---------------------------------------------------------------------------
# Residents
# ---------------------------------------------------------------------------


class VisitorViewSet(UnitScopedViewSet):
    """Pre-approve visitors and respond to visitors waiting at the gate."""

    queryset = Visitor.objects.select_related('unit__tower', 'gate')
    filterset_fields = ['status', 'visitor_type']
    search_fields = ['name', 'company', 'phone', 'vehicle_no']
    http_method_names = ['get', 'post']

    def get_serializer_class(self):
        return PreApproveSerializer if self.action == 'create' else VisitorSerializer

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, 'swagger_fake_view', False):
            return qs
        expire_stale_visitors(qs)
        bucket = self.request.query_params.get('bucket')
        if bucket:
            if bucket not in BUCKETS:
                raise ValidationError({'bucket': f'One of: {", ".join(BUCKETS)}'})
            qs = qs.filter(status__in=BUCKETS[bucket])
        return qs

    @extend_schema(parameters=[OpenApiParameter('bucket', str, enum=list(BUCKETS))])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def perform_create(self, serializer):
        serializer.save(unit=self.unit, community=self.community, created_by=self.request.user,
                        status=S.EXPECTED, pass_code=new_pass_code(self.community))

    def _respond(self, to, allowed_from, message, **extra):
        v = _transition(self.get_object(), allowed_from, to, self.request.user,
                        responded_by=self.request.user, responded_at=timezone.now(), **extra)
        notify_community_staff(v.community, GUARD_ROLES, message, f'{v.name} · {v.unit.label}', CAT.GATE,
                               {'visitor_id': v.id, 'status': v.status})
        return Response(VisitorSerializer(v).data)

    @extend_schema(request=None, responses=VisitorSerializer)
    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        """Allow a visitor waiting at the gate."""
        return self._respond(S.INSIDE, [S.WAITING], 'Entry approved', checked_in_at=timezone.now())

    @extend_schema(request=None, responses=VisitorSerializer)
    @action(detail=True, methods=['post'])
    def deny(self, request, pk=None):
        return self._respond(S.DENIED, [S.WAITING], 'Entry denied')

    @extend_schema(request=None, responses=VisitorSerializer)
    @action(detail=True, methods=['post'], url_path='leave-at-gate')
    def leave_at_gate(self, request, pk=None):
        return self._respond(S.LEFT_AT_GATE, [S.WAITING], 'Leave delivery at gate')

    @extend_schema(request=None, responses=VisitorSerializer)
    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        v = _transition(self.get_object(), [S.EXPECTED], S.CANCELLED, request.user)
        return Response(VisitorSerializer(v).data)

    @extend_schema(request=None, responses=VisitorSerializer)
    @action(detail=True, methods=['post'], url_path='mark-exit')
    def mark_exit(self, request, pk=None):
        v = _transition(self.get_object(), [S.INSIDE], S.EXITED, request.user, checked_out_at=timezone.now())
        return Response(VisitorSerializer(v).data)


class FrequentEntryViewSet(UnitScopedViewSet):
    serializer_class = FrequentEntrySerializer
    queryset = FrequentEntry.objects.all()
    filterset_fields = ['is_active', 'visitor_type']

    def perform_create(self, serializer):
        serializer.save(unit=self.unit, created_by=self.request.user, pass_code=new_pass_code(self.community))


class KidExitViewSet(UnitScopedCreateListViewSet):
    """Allow children to leave the premises unaccompanied for a time window."""

    serializer_class = KidExitSerializer
    queryset = KidExitPermission.objects.prefetch_related('children').select_related('unit__tower')
    filterset_fields = ['status']

    def perform_create(self, serializer):
        k = serializer.save(unit=self.unit, created_by=self.request.user)
        names = ', '.join(c.name for c in k.children.all())
        notify_community_staff(self.community, GUARD_ROLES, 'Kid exit allowed', f'{names} · {self.unit.label}',
                               CAT.SECURITY, {'kid_exit_id': k.id})

    @extend_schema(request=None, responses=KidExitSerializer)
    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        k = self.get_object()
        k.status = KidExitPermission.Status.CANCELLED
        k.save(update_fields=['status'])
        return Response(KidExitSerializer(k, context=self.get_serializer_context()).data)


class SOSViewSet(UnitScopedCreateListViewSet):
    """Raise an emergency alert. Guards, managers and your household are notified instantly."""

    serializer_class = SOSAlertSerializer
    queryset = SOSAlert.objects.select_related('unit__tower', 'raised_by')

    def perform_create(self, serializer):
        a = serializer.save(unit=self.unit, community=self.community, raised_by=self.request.user)
        title = f'SOS: {a.get_alert_type_display()}'
        body = f'{self.unit.label} · {self.request.user}'
        notify_community_staff(self.community, GUARD_ROLES, title, body, CAT.SECURITY, {'sos_id': a.id})
        notify_unit(self.unit, title, body, CAT.SECURITY, {'sos_id': a.id}, exclude=self.request.user)

    @extend_schema(request=None, responses=SOSAlertSerializer)
    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        a = self.get_object()
        if a.status != SOSAlert.Status.ACTIVE:
            raise ValidationError({'status': 'Only active alerts can be cancelled.'})
        a.status = SOSAlert.Status.CANCELLED
        a.save(update_fields=['status'])
        notify_community_staff(a.community, GUARD_ROLES, 'SOS cancelled', a.unit.label, CAT.SECURITY, {'sos_id': a.id})
        return Response(SOSAlertSerializer(a).data)


# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------


class GuardEntryResultSerializer(CodeLookupSerializer):
    detail_message = serializers.CharField()


class GuardVisitorViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, GuardViewSet):
    """Gate console: verify codes, check visitors in/out, raise walk-in approval requests."""

    serializer_class = VisitorSerializer
    queryset = Visitor.objects.select_related('unit__tower', 'gate')
    filterset_fields = ['status', 'visitor_type', 'unit', 'is_walk_in']
    search_fields = ['name', 'phone', 'vehicle_no', 'company', 'unit__number']

    def _gate(self, gate_id, community):
        if not gate_id:
            return None
        gate = Gate.objects.filter(pk=gate_id, community=community).first()
        if gate is None:
            raise ValidationError({'gate': 'Unknown gate for this community.'})
        return gate

    @extend_schema(request=CodeSerializer, responses=CodeLookupSerializer)
    @action(detail=False, methods=['post'])
    def verify(self, request):
        """Look up a 6-digit code (visitor pass, frequent entry or daily help) without admitting."""
        s = CodeSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        match = resolve_code(s.validated_data['code'], community_ids_for(request.user, self.roles))
        if match is None:
            raise NotFound('Invalid or expired code.')
        return Response(CodeLookupSerializer(match.as_dict()).data)

    @extend_schema(request=CodeSerializer, responses=GuardEntryResultSerializer)
    @action(detail=False, methods=['post'], url_path='check-in')
    def check_in(self, request):
        """Admit whoever the code belongs to and notify their unit(s)."""
        s = CodeSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        code = s.validated_data['code']
        match = resolve_code(code, community_ids_for(request.user, self.roles))
        if match is None:
            raise NotFound('Invalid or expired code.')
        if not match.allowed:
            raise ValidationError({'code': match.reason})
        gate = self._gate(s.validated_data.get('gate'), match.community)
        now = timezone.now()

        if match.kind == 'visitor':
            v = match.obj
            _transition(v, [S.EXPECTED], S.INSIDE, request.user, checked_in_at=now, gate=gate)
            notify_unit(v.unit, f'{v.name} has arrived', v.get_visitor_type_display(), CAT.GATE,
                        {'visitor_id': v.id}, pref='visitor_at_gate')
        elif match.kind == 'frequent_entry':
            e = match.obj
            v = Visitor.objects.create(
                community=match.community, unit=e.unit, name=e.name, phone=e.phone, visitor_type=e.visitor_type,
                company=e.company, status=S.INSIDE, pass_code=code, checked_in_at=now, gate=gate,
                created_by=request.user,
            )
            notify_unit(e.unit, f'{e.name} has arrived', 'Frequent entry', CAT.GATE, {'visitor_id': v.id},
                        pref='visitor_at_gate')
        else:
            helper = match.obj
            if helper.attendance.filter(check_out__isnull=True).exists():
                raise ValidationError({'code': f'{helper.name} is already inside.'})
            DailyHelpAttendance.objects.create(helper=helper, date=community_today(match.community), check_in=now,
                                               gate=gate, marked_by=request.user)
            for a in helper.assignments.select_related('unit'):
                notify_unit(a.unit, f'{helper.name} checked in', helper.role, CAT.DAILY_HELP,
                            {'helper_id': helper.id}, pref='daily_help_entry')
        return Response({**match.as_dict(), 'detail_message': f'{match.obj.name} checked in.'})

    @extend_schema(request=WalkInSerializer, responses=VisitorSerializer)
    @action(detail=False, methods=['post'], url_path='walk-in')
    def walk_in(self, request):
        """Visitor without a pass: residents get an approve/deny request in the app."""
        s = WalkInSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        unit = s.validated_data['unit']
        community = unit.community
        self.assert_can_manage(community)
        if s.validated_data.get('gate') and s.validated_data['gate'].community_id != community.pk:
            raise ValidationError({'gate': 'Unknown gate for this community.'})
        needs_approval = community.settings.get('require_visitor_approval', True)
        v = s.save(community=community, is_walk_in=True, created_by=request.user,
                   status=S.WAITING if needs_approval else S.INSIDE,
                   checked_in_at=None if needs_approval else timezone.now())
        notify_unit(unit, f'{v.name} is at the gate' if needs_approval else f'{v.name} has entered',
                    v.company or v.get_visitor_type_display(), CAT.GATE, {'visitor_id': v.id, 'action': 'respond'},
                    pref='visitor_at_gate')
        return Response(VisitorSerializer(v).data, status=201)

    @extend_schema(request=None, responses=VisitorSerializer)
    @action(detail=True, methods=['post'], url_path='check-out')
    def check_out(self, request, pk=None):
        v = _transition(self.get_object(), [S.INSIDE], S.EXITED, request.user, checked_out_at=timezone.now())
        return Response(VisitorSerializer(v).data)


class GuardDailyHelpViewSet(mixins.ListModelMixin, GuardViewSet):
    """Daily help in the community; ``?inside=true`` lists who is inside now."""

    serializer_class = DailyHelpSerializer
    queryset = DailyHelp.objects.all()
    search_fields = ['name', 'phone', 'role']

    def get_queryset(self):
        qs = super().get_queryset()
        qs = helpers_queryset().filter(pk__in=qs.values('pk'))
        if self.request.query_params.get('inside') == 'true':
            qs = qs.filter(is_inside=True)
        return qs

    @extend_schema(parameters=[OpenApiParameter('inside', bool)])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    @extend_schema(request=None, responses=DailyHelpSerializer)
    @action(detail=True, methods=['post'], url_path='check-out')
    def check_out(self, request, pk=None):
        helper = self.get_object()
        visit = helper.attendance.filter(check_out__isnull=True).first()
        if visit is None:
            raise ValidationError({'detail': f'{helper.name} is not inside.'})
        visit.check_out = timezone.now()
        visit.save(update_fields=['check_out'])
        for a in helper.assignments.select_related('unit'):
            notify_unit(a.unit, f'{helper.name} checked out', helper.role, CAT.DAILY_HELP, {'helper_id': helper.id},
                        pref='daily_help_entry')
        return Response(DailyHelpSerializer(self.get_queryset().get(pk=helper.pk)).data)


class GuardKidExitViewSet(mixins.ListModelMixin, GuardViewSet):
    """Children currently allowed to exit."""

    serializer_class = KidExitSerializer
    queryset = KidExitPermission.objects.prefetch_related('children').select_related('unit__tower')
    community_lookup = 'unit__tower__community'

    def get_queryset(self):
        now = timezone.now()
        return super().get_queryset().filter(status=KidExitPermission.Status.ACTIVE, allowed_from__lte=now,
                                             allowed_until__gte=now)


class GuardSOSViewSet(mixins.ListModelMixin, GuardViewSet):
    serializer_class = SOSAlertSerializer
    queryset = SOSAlert.objects.select_related('unit__tower', 'raised_by')
    filterset_fields = ['status', 'alert_type']

    def _update(self, status, field, title):
        a = self.get_object()
        if a.status in (SOSAlert.Status.RESOLVED, SOSAlert.Status.CANCELLED):
            raise ValidationError({'status': 'Alert is already closed.'})
        a.status, a.handled_by = status, self.request.user
        setattr(a, field, timezone.now())
        a.save()
        notify_unit(a.unit, title, f'Handled by {self.request.user}', CAT.SECURITY, {'sos_id': a.id})
        return Response(SOSAlertSerializer(a).data)

    @extend_schema(request=None, responses=SOSAlertSerializer)
    @action(detail=True, methods=['post'])
    def acknowledge(self, request, pk=None):
        return self._update(SOSAlert.Status.ACKNOWLEDGED, 'acknowledged_at', 'Security is on the way')

    @extend_schema(request=None, responses=SOSAlertSerializer)
    @action(detail=True, methods=['post'])
    def resolve(self, request, pk=None):
        return self._update(SOSAlert.Status.RESOLVED, 'resolved_at', 'Your SOS alert was resolved')


# ---------------------------------------------------------------------------
# Management (read-only logs)
# ---------------------------------------------------------------------------


class ManageVisitorLogViewSet(ManageReadOnlyViewSet):
    tower_lookup = 'unit__tower'
    serializer_class = VisitorSerializer
    queryset = Visitor.objects.select_related('unit__tower', 'gate')
    filterset_fields = {'status': ['exact'], 'visitor_type': ['exact'], 'unit__tower': ['exact'],
                        'created_at': ['gte', 'lte'], 'community': ['exact']}
    search_fields = ['name', 'phone', 'vehicle_no', 'company', 'unit__number']


class ManageSOSViewSet(ManageReadOnlyViewSet):
    tower_lookup = 'unit__tower'
    serializer_class = SOSAlertSerializer
    queryset = SOSAlert.objects.select_related('unit__tower', 'raised_by')
    filterset_fields = ['status', 'alert_type', 'community']
    roles = MANAGER_ROLES
