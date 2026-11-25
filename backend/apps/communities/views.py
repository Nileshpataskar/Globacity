from django.db import IntegrityError, transaction
from django.db.models import Count
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.generics import GenericAPIView
from rest_framework.response import Response

from apps.accounts.models import User, UserSettings
from apps.accounts.phone import normalize_phone
from apps.core.permissions import MANAGER_ROLES, IsPlatformAdmin
from apps.core.scoping import ManageViewSet, UnitScopedMixin
from apps.notifications.models import Notification
from apps.notifications.service import notify, notify_community_staff

from .models import Community, EmergencyContact, Gate, Membership, StaffMember, Tower, Unit
from .serializers import (
    CommunityPublicSerializer,
    CommunitySerializer,
    ContactItemSerializer,
    DirectoryResidentSerializer,
    DirectoryStaffSerializer,
    EmergencyContactSerializer,
    GateSerializer,
    GenerateUnitsResponseSerializer,
    GenerateUnitsSerializer,
    ManagedCommunitySerializer,
    ManageMembershipSerializer,
    MembershipSerializer,
    PersonalContactSerializer,
    StaffMemberSerializer,
    TowerPublicSerializer,
    TowerSerializer,
    UnitPublicSerializer,
    UnitSerializer,
)


def get_or_create_user(phone, full_name=''):
    phone, country = normalize_phone(phone)
    user, _ = User.objects.get_or_create(
        phone=phone, defaults={'full_name': full_name, 'country': country, 'language': country.default_language}
    )
    return user


# ---------------------------------------------------------------------------
# Platform admin
# ---------------------------------------------------------------------------


class PlatformCommunityViewSet(viewsets.ModelViewSet):
    """Register communities under a city. Assign their first admin via /manage/staff/."""

    permission_classes = [IsPlatformAdmin]
    serializer_class = CommunitySerializer
    queryset = Community.objects.select_related('city__country')
    filterset_fields = ['city', 'city__country', 'is_active']
    search_fields = ['name', 'address']


# ---------------------------------------------------------------------------
# Community management
# ---------------------------------------------------------------------------


class ManageCommunityViewSet(ManageViewSet):
    serializer_class = ManagedCommunitySerializer
    queryset = Community.objects.select_related('city__country')
    community_lookup = 'pk'
    tower_lookup = 'towers'
    http_method_names = ['get', 'patch']

    def community_from(self, data, instance=None):
        return instance


class ManageTowerViewSet(ManageViewSet):
    serializer_class = TowerSerializer
    queryset = Tower.objects.annotate(units_count=Count('units'))
    tower_lookup = 'pk'

    def tower_from(self, data, instance=None):
        # Tower admins may edit their own tower's settings; creating towers needs a community admin.
        return instance
    filterset_fields = ['community']
    search_fields = ['name', 'code']

    @extend_schema(request=GenerateUnitsSerializer, responses=GenerateUnitsResponseSerializer)
    @action(detail=True, methods=['post'], url_path='generate-units')
    def generate_units(self, request, pk=None):
        """Bulk-create units, e.g. floors 1-20 with 4 units each -> 101..2004."""
        tower = self.get_object()
        s = GenerateUnitsSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        d = s.validated_data
        existing = set(tower.units.values_list('number', flat=True))
        new = []
        for floor in range(d['floor_from'], d['floor_to'] + 1):
            for index in range(1, d['units_per_floor'] + 1):
                number = d['number_format'].format(floor=floor, index=index)
                if number not in existing:
                    existing.add(number)
                    new.append(Unit(tower=tower, number=number, floor=floor, unit_type=d['unit_type']))
        Unit.objects.bulk_create(new)
        total = (d['floor_to'] - d['floor_from'] + 1) * d['units_per_floor']
        if d['floor_to'] > tower.floors:
            tower.floors = d['floor_to']
            tower.save(update_fields=['floors'])
        return Response({'created': len(new), 'skipped': total - len(new)})


class ManageUnitViewSet(ManageViewSet):
    serializer_class = UnitSerializer
    queryset = Unit.objects.select_related('tower')
    community_lookup = 'tower__community'
    tower_lookup = 'tower'
    filterset_fields = ['tower', 'unit_type', 'floor']
    search_fields = ['number']

    def community_from(self, data, instance=None):
        tower = data.get('tower') or getattr(instance, 'tower', None)
        return tower.community if tower else None


class ManageGateViewSet(ManageViewSet):
    serializer_class = GateSerializer
    queryset = Gate.objects.all()
    filterset_fields = ['community', 'is_active']


class ManageMembershipViewSet(ManageViewSet):
    """Approve join requests or add residents directly."""

    serializer_class = ManageMembershipSerializer
    queryset = Membership.objects.select_related('user', 'unit__tower')
    community_lookup = 'unit__tower__community'
    tower_lookup = 'unit__tower'
    filterset_fields = ['status', 'role', 'unit', 'unit__tower']
    search_fields = ['user__full_name', 'user__phone', 'unit__number']
    http_method_names = ['get', 'post', 'delete']

    def community_from(self, data, instance=None):
        unit = data.get('unit') or getattr(instance, 'unit', None)
        return unit.community if unit else None

    def perform_create(self, serializer):
        data = serializer.validated_data
        self.assert_can_manage(self.community_from(data), self.tower_from(data))
        phone = data.pop('user_phone', None)
        full_name = data.pop('full_name', '')
        if not phone:
            raise ValidationError({'user_phone': 'This field is required.'})
        user = get_or_create_user(phone, full_name)
        try:
            serializer.save(user=user, status=Membership.Status.APPROVED, approved_by=self.request.user,
                            approved_at=timezone.now())
        except IntegrityError:
            raise ValidationError({'user_phone': 'This person is already linked to the unit.'})

    def _set_status(self, membership, status, title):
        membership.status = status
        membership.approved_by = self.request.user
        membership.approved_at = timezone.now()
        membership.save(update_fields=['status', 'approved_by', 'approved_at'])
        notify([membership.user], title, membership.unit.label, Notification.Category.COMMUNITY,
               {'membership_id': membership.id})
        return Response(ManageMembershipSerializer(membership).data)

    @extend_schema(request=None, responses=ManageMembershipSerializer)
    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        return self._set_status(self.get_object(), Membership.Status.APPROVED, 'Your unit request was approved')

    @extend_schema(request=None, responses=ManageMembershipSerializer)
    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        return self._set_status(self.get_object(), Membership.Status.REJECTED, 'Your unit request was declined')

    @extend_schema(request=None, responses=ManageMembershipSerializer)
    @action(detail=True, methods=['post'], url_path='move-out')
    def move_out(self, request, pk=None):
        return self._set_status(self.get_object(), Membership.Status.MOVED_OUT, 'You have been marked as moved out')


class ManageStaffViewSet(ManageViewSet):
    """Staff and roles. Platform admins use this to assign a community's first admin."""

    serializer_class = StaffMemberSerializer
    queryset = StaffMember.objects.select_related('user').prefetch_related('towers')
    readable_by_tower_admins = True
    filterset_fields = ['community', 'role', 'is_active']
    search_fields = ['name', 'phone', 'designation']

    def _save(self, serializer, **kwargs):
        phone = serializer.validated_data.pop('user_phone', None)
        if phone:
            user = get_or_create_user(phone, serializer.validated_data.get('name', ''))
            kwargs['user'] = user
            serializer.validated_data.setdefault('phone', user.phone)
        try:
            serializer.save(**kwargs)
        except IntegrityError:
            raise ValidationError({'user_phone': 'This user already has that role in the community.'})

    def perform_create(self, serializer):
        self.assert_can_manage(self.community_from(serializer.validated_data))
        self._save(serializer)

    def perform_update(self, serializer):
        self.assert_can_manage(self.community_from(serializer.validated_data, serializer.instance))
        self._save(serializer)


class ManageEmergencyContactViewSet(ManageViewSet):
    serializer_class = EmergencyContactSerializer
    queryset = EmergencyContact.objects.filter(group=EmergencyContact.Group.COMMUNITY)
    filterset_fields = ['community']

    def get_create_kwargs(self):
        return {'group': EmergencyContact.Group.COMMUNITY}


# ---------------------------------------------------------------------------
# Residents
# ---------------------------------------------------------------------------


class CommunityBrowseViewSet(viewsets.ReadOnlyModelViewSet):
    """Find a community to join, then pick a tower and unit."""

    serializer_class = CommunityPublicSerializer
    queryset = Community.objects.filter(is_active=True).select_related('city__country')
    search_fields = ['name', 'address', 'city__name']
    filterset_fields = ['city', 'city__country']

    @extend_schema(responses=TowerPublicSerializer(many=True))
    @action(detail=True, methods=['get'], pagination_class=None)
    def towers(self, request, pk=None):
        return Response(TowerPublicSerializer(self.get_object().towers.all(), many=True).data)

    @extend_schema(
        parameters=[OpenApiParameter('tower', str, required=True), OpenApiParameter('search', str)],
        responses=UnitPublicSerializer(many=True),
    )
    @action(detail=True, methods=['get'], pagination_class=None, filter_backends=[])
    def units(self, request, pk=None):
        tower = request.query_params.get('tower')
        if not tower:
            raise ValidationError({'tower': 'This query parameter is required.'})
        units = Unit.objects.filter(tower__community=self.get_object(), tower_id=tower)
        if request.query_params.get('search'):
            units = units.filter(number__icontains=request.query_params['search'])
        return Response(UnitPublicSerializer(units[:200], many=True).data)


class MyUnitsViewSet(mixins.ListModelMixin, mixins.CreateModelMixin, mixins.DestroyModelMixin,
                     viewsets.GenericViewSet):
    """My properties. POST = request to join a unit; DELETE = cancel request / leave."""

    serializer_class = MembershipSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Membership.objects.none()
        return (Membership.objects.filter(user=self.request.user)
                .exclude(status=Membership.Status.MOVED_OUT)
                .select_related('unit__tower__community__city__country'))

    def perform_create(self, serializer):
        unit = serializer.validated_data['unit']
        auto = unit.tower.approval_mode == Tower.ApprovalMode.AUTO
        with transaction.atomic():
            Membership.objects.filter(user=self.request.user, unit=unit, status=Membership.Status.REJECTED).delete()
            if auto:
                m = serializer.save(user=self.request.user, status=Membership.Status.APPROVED,
                                    approved_at=timezone.now(), note='Auto-approved by tower setting')
            else:
                m = serializer.save(user=self.request.user, status=Membership.Status.PENDING)
        if auto:
            notify([self.request.user], f'Welcome to {m.unit.community.name}', m.unit.label,
                   Notification.Category.COMMUNITY, {'membership_id': m.id})
        notify_community_staff(
            m.unit.community, MANAGER_ROLES, 'New resident joined' if auto else 'New resident request',
            f'{self.request.user} {"joined" if auto else "requested access to"} {m.unit.label}',
            Notification.Category.COMMUNITY, {'membership_id': m.id}, tower=m.unit.tower,
        )


class ResidentDirectoryView(UnitScopedMixin, GenericAPIView):
    serializer_class = DirectoryResidentSerializer
    queryset = Membership.objects.none()

    @extend_schema(parameters=[OpenApiParameter('search', str)], responses=DirectoryResidentSerializer(many=True))
    def get(self, request):
        q = request.query_params.get('search', '').strip()
        memberships = (Membership.objects.filter(unit__tower__community=self.community,
                                                 status=Membership.Status.APPROVED)
                       .select_related('user', 'unit__tower').order_by('user__full_name'))
        if q:
            memberships = memberships.filter(user__full_name__icontains=q) | memberships.filter(unit__number__icontains=q)
        prefs = {s.user_id: s.privacy_prefs for s in UserSettings.objects.filter(user__in=[m.user for m in memberships])}
        rows, seen = [], set()
        for m in memberships:
            p = prefs.get(m.user_id, {})
            if not p.get('show_in_directory', True) or (m.user_id, m.unit_id) in seen:
                continue
            seen.add((m.user_id, m.unit_id))
            rows.append({
                'user_id': m.user_id,
                'name': m.user.full_name or 'Resident',
                'unit': m.unit.label if p.get('show_unit', True) else None,
                'phone': m.user.phone if p.get('show_phone', False) else None,
                'role': m.role,
                'can_message': p.get('allow_messages', True) and m.user_id != request.user.pk,
            })
        page = self.paginate_queryset(rows)
        return self.get_paginated_response(DirectoryResidentSerializer(page, many=True).data)


class StaffDirectoryView(UnitScopedMixin, GenericAPIView):
    serializer_class = DirectoryStaffSerializer
    queryset = StaffMember.objects.none()

    @extend_schema(responses=DirectoryStaffSerializer(many=True))
    def get(self, request):
        staff = StaffMember.objects.filter(community=self.community, is_active=True, show_in_directory=True)
        page = self.paginate_queryset(staff)
        return self.get_paginated_response(DirectoryStaffSerializer(page, many=True).data)


class EmergencyContactsViewSet(UnitScopedMixin, viewsets.GenericViewSet):
    """Country emergency numbers + community contacts + your personal contacts."""

    serializer_class = PersonalContactSerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return EmergencyContact.objects.none()
        return EmergencyContact.objects.filter(user=self.request.user, group=EmergencyContact.Group.PERSONAL)

    @extend_schema(responses=ContactItemSerializer(many=True))
    def list(self, request):
        country = self.community.country
        items = [
            {'id': None, 'name': key.replace('_', ' ').title(), 'phone': number, 'group': 'public', 'icon': key}
            for key, number in (country.emergency_numbers or {}).items()
        ]
        for c in EmergencyContact.objects.filter(community=self.community, group=EmergencyContact.Group.COMMUNITY):
            items.append({'id': str(c.id), 'name': c.name, 'phone': c.phone, 'group': 'community', 'icon': c.icon})
        for c in self.get_queryset():
            items.append({'id': str(c.id), 'name': c.name, 'phone': c.phone, 'group': 'personal', 'icon': c.icon})
        return Response(ContactItemSerializer(items, many=True).data)

    @extend_schema(request=PersonalContactSerializer, responses=PersonalContactSerializer)
    def create(self, request):
        s = PersonalContactSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        s.save(user=request.user, group=EmergencyContact.Group.PERSONAL)
        return Response(s.data, status=201)

    def destroy(self, request, pk=None):
        self.get_object().delete()
        return Response(status=204)
