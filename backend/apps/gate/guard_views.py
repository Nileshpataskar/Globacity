"""Guard app endpoints: shifts, summary, vehicles, staff attendance, incidents, IoT gates, directory."""

import re

from django.db.models import Q
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema, inline_serializer
from rest_framework import mixins, serializers
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.accounts.models import UserSettings
from apps.communities.models import Community, Gate, Membership, StaffMember, Unit
from apps.core.permissions import GUARD_ROLES, MANAGER_ROLES, IsGuard, community_ids_for
from apps.core.scoping import GuardViewSet, ManageViewSet, parse_uuid
from apps.core.utils import community_today
from apps.household.models import DailyHelpAttendance, Vehicle
from apps.notifications.models import Notification
from apps.notifications.service import notify_community_staff, notify_unit

from .iot import open_gate
from .models import GateEvent, GuardShift, Incident, KidExitPermission, SOSAlert, StaffAttendance, Visitor, VehicleLog


def guard_communities(user):
    ids = community_ids_for(user, GUARD_ROLES)
    qs = Community.objects.filter(is_active=True)
    return qs if ids is None else qs.filter(pk__in=ids)


def resolve_community(request):
    """Community from ?community= (validated) or the guard's only/first community."""
    communities = guard_communities(request.user)
    cid = request.query_params.get('community') or getattr(request, 'data', {}).get('community')
    if cid:
        community = communities.filter(pk=parse_uuid(cid, 'community')).first()
        if community is None:
            raise PermissionDenied('You are not on duty for this community.')
        return community
    community = communities.order_by('name').first()
    if community is None:
        raise PermissionDenied('No community assigned.')
    return community


def normalize_plate(number):
    return re.sub(r'[^A-Z0-9]', '', (number or '').upper())


# ---------------------------------------------------------------------------
# Serializers
# ---------------------------------------------------------------------------


class GateMiniSerializer(serializers.ModelSerializer):
    class Meta:
        model = Gate
        fields = ['id', 'name', 'iot_enabled']


class GuardShiftSerializer(serializers.ModelSerializer):
    gate_name = serializers.CharField(source='gate.name', read_only=True, default=None)
    shift_label = serializers.CharField(source='get_shift_display', read_only=True)

    class Meta:
        model = GuardShift
        fields = ['id', 'community', 'gate', 'gate_name', 'shift', 'shift_label', 'started_at', 'ended_at']
        read_only_fields = ['started_at', 'ended_at']


class VehicleLogSerializer(serializers.ModelSerializer):
    unit_label = serializers.CharField(source='unit.label', read_only=True, default=None)
    gate_name = serializers.CharField(source='gate.name', read_only=True, default=None)
    is_resident = serializers.SerializerMethodField()

    class Meta:
        model = VehicleLog
        fields = ['id', 'number', 'direction', 'unit', 'unit_label', 'is_resident', 'note', 'gate', 'gate_name',
                  'created_at']
        read_only_fields = ['unit']

    def get_is_resident(self, obj) -> bool:
        return obj.vehicle_id is not None


class StaffStatusSerializer(serializers.Serializer):
    id = serializers.UUIDField()
    name = serializers.CharField()
    role = serializers.CharField()
    designation = serializers.CharField()
    shift = serializers.CharField()
    phone = serializers.CharField()
    is_inside = serializers.BooleanField()
    check_in = serializers.DateTimeField(allow_null=True)
    check_out = serializers.DateTimeField(allow_null=True)


class IncidentSerializer(serializers.ModelSerializer):
    reported_by_name = serializers.CharField(source='reported_by.full_name', read_only=True, default=None)
    unit_label = serializers.CharField(source='unit.label', read_only=True, default=None)

    class Meta:
        model = Incident
        fields = ['id', 'community', 'title', 'description', 'category', 'severity', 'location', 'unit', 'unit_label',
                  'photo', 'status', 'resolution', 'reported_by_name', 'created_at', 'updated_at']
        read_only_fields = ['community']


class SummarySerializer(serializers.Serializer):
    community = serializers.DictField()
    visitors_today = serializers.IntegerField()
    inside_now = serializers.IntegerField()
    waiting_approval = serializers.IntegerField()
    active_passes = serializers.IntegerField()
    deliveries_today = serializers.IntegerField()
    cabs_today = serializers.IntegerField()
    daily_help_inside = serializers.IntegerField()
    staff_on_duty = serializers.IntegerField()
    vehicles_in_today = serializers.IntegerField()
    active_sos = serializers.IntegerField()
    open_incidents = serializers.IntegerField()
    kid_exits_active = serializers.IntegerField()


class DirectoryEntrySerializer(serializers.Serializer):
    unit_id = serializers.UUIDField()
    unit_label = serializers.CharField()
    residents = serializers.ListField(child=serializers.DictField())
    vehicles = serializers.ListField(child=serializers.CharField())


# ---------------------------------------------------------------------------
# Views
# ---------------------------------------------------------------------------


class GuardContextView(APIView):
    """Communities and gates the guard can work at, plus the open shift."""

    permission_classes = [IsAuthenticated, IsGuard]

    @extend_schema(responses=inline_serializer('GuardContext', {
        'communities': serializers.ListField(child=serializers.DictField()),
        'shift': GuardShiftSerializer(allow_null=True),
    }), tags=['Guard · context'])
    def get(self, request):
        shift = GuardShift.objects.filter(guard=request.user, ended_at__isnull=True).select_related('gate').first()
        return Response({
            'communities': [
                {'id': str(c.id), 'name': c.name,
                 'gates': GateMiniSerializer(c.gates.filter(is_active=True), many=True).data}
                for c in guard_communities(request.user)
            ],
            'shift': GuardShiftSerializer(shift).data if shift else None,
        })


class GuardShiftViewSet(mixins.ListModelMixin, GuardViewSet):
    serializer_class = GuardShiftSerializer
    queryset = GuardShift.objects.select_related('gate')

    def get_queryset(self):
        return super().get_queryset().filter(guard=self.request.user)

    @extend_schema(request=GuardShiftSerializer, responses=GuardShiftSerializer)
    @action(detail=False, methods=['post'])
    def start(self, request):
        """Start a shift (ends any open one)."""
        s = GuardShiftSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        community = s.validated_data['community']
        self.assert_can_manage(community)
        gate = s.validated_data.get('gate')
        if gate and gate.community_id != community.pk:
            raise ValidationError({'gate': 'Gate is not in this community.'})
        GuardShift.objects.filter(guard=request.user, ended_at__isnull=True).update(ended_at=timezone.now())
        shift = s.save(guard=request.user)
        return Response(GuardShiftSerializer(shift).data, status=201)

    @extend_schema(request=None, responses=GuardShiftSerializer)
    @action(detail=True, methods=['post'])
    def end(self, request, pk=None):
        shift = self.get_object()
        if shift.ended_at is None:
            shift.ended_at = timezone.now()
            shift.save(update_fields=['ended_at'])
        return Response(GuardShiftSerializer(shift).data)


class GuardSummaryView(APIView):
    """Today's numbers for the guard dashboard."""

    permission_classes = [IsAuthenticated, IsGuard]

    @extend_schema(parameters=[OpenApiParameter('community', str)], responses=SummarySerializer, tags=['Guard · summary'])
    def get(self, request):
        c = resolve_community(request)
        today = community_today(c)
        now = timezone.now()
        visitors = Visitor.objects.filter(community=c)
        today_visits = visitors.filter(Q(checked_in_at__date=today) | Q(created_at__date=today))
        return Response(SummarySerializer({
            'community': {'id': str(c.id), 'name': c.name},
            'visitors_today': today_visits.exclude(status__in=['expected', 'cancelled', 'expired']).count(),
            'inside_now': visitors.filter(status=Visitor.Status.INSIDE).count(),
            'waiting_approval': visitors.filter(status=Visitor.Status.WAITING).count(),
            'active_passes': visitors.filter(status=Visitor.Status.EXPECTED, valid_until__gte=now).count(),
            'deliveries_today': today_visits.filter(visitor_type='delivery').count(),
            'cabs_today': today_visits.filter(visitor_type='cab').count(),
            'daily_help_inside': DailyHelpAttendance.objects.filter(helper__community=c, check_out__isnull=True).count(),
            'staff_on_duty': StaffAttendance.objects.filter(staff__community=c, date=today, check_out__isnull=True).count(),
            'vehicles_in_today': VehicleLog.objects.filter(community=c, direction='in', created_at__date=today).count(),
            'active_sos': SOSAlert.objects.filter(community=c, status__in=['active', 'acknowledged']).count(),
            'open_incidents': Incident.objects.filter(community=c).exclude(status='resolved').count(),
            'kid_exits_active': KidExitPermission.objects.filter(unit__tower__community=c, status='active',
                                                                 allowed_from__lte=now, allowed_until__gte=now).count(),
        }).data)


class GuardVehicleViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, GuardViewSet):
    """Vehicle entry/exit log. Resident vehicles are matched automatically by plate."""

    serializer_class = VehicleLogSerializer
    queryset = VehicleLog.objects.select_related('unit__tower', 'gate')
    filterset_fields = ['direction', 'community']
    search_fields = ['number']

    def perform_create(self, serializer):
        community = resolve_community(self.request)
        plate = normalize_plate(serializer.validated_data['number'])
        vehicle = next((v for v in Vehicle.objects.filter(unit__tower__community=community).select_related('unit')
                        if normalize_plate(v.number) == plate), None)
        gate = serializer.validated_data.get('gate')
        if gate and gate.community_id != community.pk:
            raise ValidationError({'gate': 'Gate is not in this community.'})
        log = serializer.save(community=community, logged_by=self.request.user, vehicle=vehicle,
                              unit=vehicle.unit if vehicle else None)
        if vehicle and log.direction == 'in':
            notify_unit(vehicle.unit, f'{vehicle.number} entered', log.gate.name if log.gate else 'Gate',
                        Notification.Category.GATE, {'vehicle_log_id': log.id})

    @extend_schema(parameters=[OpenApiParameter('number', str, required=True)],
                   responses=inline_serializer('VehicleLookup', {
                       'registered': serializers.BooleanField(), 'unit_label': serializers.CharField(allow_null=True),
                       'make_model': serializers.CharField(allow_null=True)}))
    @action(detail=False, methods=['get'])
    def lookup(self, request):
        community = resolve_community(request)
        plate = normalize_plate(request.query_params.get('number'))
        v = next((v for v in Vehicle.objects.filter(unit__tower__community=community).select_related('unit__tower')
                  if plate and normalize_plate(v.number) == plate), None)
        return Response({'registered': v is not None, 'unit_label': v.unit.label if v else None,
                         'make_model': v.make_model if v else None})


class GuardStaffViewSet(GuardViewSet):
    """Mark staff attendance (facility, housekeeping, security...)."""

    serializer_class = StaffStatusSerializer
    queryset = StaffMember.objects.filter(is_active=True)

    def _rows(self, staff):
        today = community_today(staff[0].community) if staff else None
        records = {a.staff_id: a for a in StaffAttendance.objects.filter(staff__in=staff, date=today)}
        rows = []
        for s in staff:
            a = records.get(s.pk)
            rows.append({'id': s.pk, 'name': s.name, 'role': s.get_role_display(), 'designation': s.designation,
                         'shift': s.shift, 'phone': s.phone, 'is_inside': bool(a and a.check_out is None),
                         'check_in': a.check_in if a else None, 'check_out': a.check_out if a else None})
        return rows

    @extend_schema(parameters=[OpenApiParameter('community', str)], responses=StaffStatusSerializer(many=True))
    def list(self, request):
        community = resolve_community(request)
        staff = list(self.get_queryset().filter(community=community).exclude(role='admin').select_related('community'))
        return Response(StaffStatusSerializer(self._rows(staff), many=True).data)

    def _mark(self, staff, check_in):
        today = community_today(staff.community)
        record = StaffAttendance.objects.filter(staff=staff, date=today).first()
        if check_in:
            if record and record.check_out is None:
                raise ValidationError({'detail': f'{staff.name} is already checked in.'})
            StaffAttendance.objects.create(staff=staff, date=today, check_in=timezone.now(), marked_by=self.request.user)
        else:
            if not record or record.check_out is not None:
                raise ValidationError({'detail': f'{staff.name} is not checked in.'})
            record.check_out = timezone.now()
            record.save(update_fields=['check_out'])
        return Response(StaffStatusSerializer(self._rows([staff])[0]).data)

    @extend_schema(request=None, responses=StaffStatusSerializer)
    @action(detail=True, methods=['post'], url_path='check-in')
    def check_in(self, request, pk=None):
        return self._mark(self.get_object(), True)

    @extend_schema(request=None, responses=StaffStatusSerializer)
    @action(detail=True, methods=['post'], url_path='check-out')
    def check_out(self, request, pk=None):
        return self._mark(self.get_object(), False)


class GuardIncidentViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, mixins.RetrieveModelMixin,
                           mixins.UpdateModelMixin, GuardViewSet):
    """Report incidents (with photo) and follow them up."""

    serializer_class = IncidentSerializer
    queryset = Incident.objects.select_related('reported_by', 'unit__tower')
    filterset_fields = ['status', 'severity', 'community']
    search_fields = ['title', 'description', 'location']
    parser_classes = [JSONParser, MultiPartParser, FormParser]
    http_method_names = ['get', 'post', 'patch']

    def perform_create(self, serializer):
        community = resolve_community(self.request)
        unit = serializer.validated_data.get('unit')
        if unit and unit.community.pk != community.pk:
            raise ValidationError({'unit': 'Unit is not in this community.'})
        incident = serializer.save(community=community, reported_by=self.request.user)
        notify_community_staff(community, MANAGER_ROLES, f'Incident: {incident.title}',
                               f'{incident.get_severity_display()} · {incident.location or "No location"}',
                               Notification.Category.SECURITY, {'incident_id': incident.id})

    def perform_update(self, serializer):
        serializer.save()


class GuardGateViewSet(mixins.ListModelMixin, GuardViewSet):
    """Gates and IoT boom-barrier control."""

    serializer_class = GateMiniSerializer
    queryset = Gate.objects.filter(is_active=True)
    pagination_class = None

    @extend_schema(request=None, responses=inline_serializer('GateOpenResult', {
        'success': serializers.BooleanField(), 'detail': serializers.CharField()}))
    @action(detail=True, methods=['post'])
    def open(self, request, pk=None):
        gate = self.get_object()
        if not gate.iot_enabled:
            raise ValidationError({'detail': f'{gate.name} has no IoT controller connected.'})
        success, detail = open_gate(gate)
        GateEvent.objects.create(gate=gate, action='open', triggered_by=request.user, success=success, detail=detail)
        return Response({'success': success, 'detail': detail})


class GuardDirectoryView(APIView):
    """Find a unit by number, resident name or vehicle plate. Phones shown only if the resident allows guard calls."""

    permission_classes = [IsAuthenticated, IsGuard]

    @extend_schema(parameters=[OpenApiParameter('search', str, required=True), OpenApiParameter('community', str)],
                   responses=DirectoryEntrySerializer(many=True), tags=['Guard · directory'])
    def get(self, request):
        community = resolve_community(request)
        q = request.query_params.get('search', '').strip()
        if len(q) < 1:
            return Response([])
        plate = normalize_plate(q)
        units = Unit.objects.filter(tower__community=community).filter(
            Q(number__icontains=q) | Q(memberships__user__full_name__icontains=q, memberships__status='approved')
            | Q(vehicles__number__icontains=q) | (Q(vehicles__number__icontains=plate) if plate else Q(pk__in=[]))
        ).select_related('tower').distinct()[:20]
        rows = []
        for u in units:
            members = Membership.objects.filter(unit=u, status='approved').select_related('user')
            prefs = {s.user_id: s.privacy_prefs for s in UserSettings.objects.filter(user__in=[m.user for m in members])}
            rows.append({
                'unit_id': u.pk, 'unit_label': u.label,
                'residents': [{'name': m.user.full_name or 'Resident', 'role': m.role,
                               'phone': m.user.phone if prefs.get(m.user_id, {}).get('allow_guard_calls', True) else None}
                              for m in members],
                'vehicles': list(u.vehicles.values_list('number', flat=True)),
            })
        return Response(DirectoryEntrySerializer(rows, many=True).data)


class ManageIncidentViewSet(ManageViewSet):
    tower_lookup = 'unit__tower'
    serializer_class = IncidentSerializer
    queryset = Incident.objects.select_related('reported_by', 'unit__tower')
    filterset_fields = ['status', 'severity', 'community']
    http_method_names = ['get', 'patch']
