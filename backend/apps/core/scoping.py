"""Base viewsets that scope every query to a unit, a community or a manager's communities."""

import uuid

from django.db.models import Q

from rest_framework import mixins, viewsets
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.permissions import IsAuthenticated

from .permissions import (
    GUARD_ROLES,
    MANAGER_ROLES,
    IsCommunityManager,
    IsGuard,
    IsUnitMember,
    can_manage_tower,
    community_ids_for,
    has_community_role,
    manager_scope,
)

UNIT_HEADER = 'X-Unit-ID'


def parse_uuid(value, field='id'):
    try:
        return uuid.UUID(str(value))
    except (TypeError, ValueError):
        raise ValidationError({field: 'Must be a valid UUID.'})


def is_schema_view(view):
    return getattr(view, 'swagger_fake_view', False)


# ---------------------------------------------------------------------------
# Resident (unit) scope
# ---------------------------------------------------------------------------


class UnitScopedMixin:
    """Gives the view ``self.membership``, ``self.unit`` and ``self.community``."""

    unit_scoped = True
    permission_classes = [IsAuthenticated, IsUnitMember]

    def get_membership(self):
        if hasattr(self, '_membership'):
            return self._membership
        from apps.communities.models import Membership

        qs = Membership.objects.select_related(
            'unit__tower__community__city__country__currency', 'user'
        ).filter(user=self.request.user, status=Membership.Status.APPROVED)
        unit_id = self.request.headers.get(UNIT_HEADER) or self.request.query_params.get('unit_id')
        if unit_id:
            membership = qs.filter(unit_id=parse_uuid(unit_id, UNIT_HEADER)).first()
            if membership is None:
                raise PermissionDenied('You are not an approved member of this unit.')
        else:
            memberships = list(qs[:2])
            if not memberships:
                raise PermissionDenied('You have no approved unit yet. Join a community first.')
            if len(memberships) > 1:
                raise ValidationError({UNIT_HEADER: 'You belong to several units. Send the X-Unit-ID header.'})
            membership = memberships[0]
        self._membership = membership
        return membership

    @property
    def membership(self):
        return self.get_membership()

    @property
    def unit(self):
        return self.get_membership().unit

    @property
    def community(self):
        return self.get_membership().unit.tower.community


class _ScopedQuerysetMixin(UnitScopedMixin):
    #: 'unit' -> rows of the caller's unit; 'community' -> rows of the caller's community.
    scope = 'unit'
    #: Override when the FK path differs, e.g. 'helper__community'.
    scope_lookup = None

    def get_queryset(self):
        qs = super().get_queryset()
        if is_schema_view(self):
            return qs.none()
        lookup = self.scope_lookup or self.scope
        return qs.filter(**{lookup: self.unit if self.scope == 'unit' else self.community})

    def get_create_kwargs(self):
        if self.scope == 'unit':
            return {'unit': self.unit}
        return {'community': self.community}

    def perform_create(self, serializer):
        serializer.save(**self.get_create_kwargs())


class UnitScopedViewSet(_ScopedQuerysetMixin, viewsets.ModelViewSet):
    pass


class UnitScopedReadOnlyViewSet(_ScopedQuerysetMixin, viewsets.ReadOnlyModelViewSet):
    pass


class UnitScopedCreateListViewSet(
    _ScopedQuerysetMixin, mixins.CreateModelMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin,
    viewsets.GenericViewSet,
):
    pass


# ---------------------------------------------------------------------------
# Community staff scope (managers, guards)
# ---------------------------------------------------------------------------


class _CommunityRoleViewSetMixin:
    roles = MANAGER_ROLES
    #: FK path from the model to Community.
    community_lookup = 'community'
    #: FK path from the model to Tower. Tower-limited admins only see rows of their towers;
    #: viewsets without it are for whole-community admins only.
    tower_lookup = None
    #: Tower-limited admins may *read* this community-wide list (e.g. charge types, staff to assign tickets to).
    readable_by_tower_admins = False

    def get_queryset(self):
        qs = super().get_queryset()
        if is_schema_view(self):
            return qs.none()
        if self.roles == MANAGER_ROLES:
            full, towers = manager_scope(self.request.user, self.roles)
            if full is not None:
                q = Q(**{f'{self.community_lookup}__in': full})
                if towers and self.tower_lookup:
                    q |= Q(**{f'{self.tower_lookup}__in': towers})
                if towers and self.readable_by_tower_admins and self.request.method in ('GET', 'HEAD', 'OPTIONS'):
                    from apps.communities.models import Tower

                    tower_communities = Tower.objects.filter(pk__in=towers).values('community_id')
                    q |= Q(**{f'{self.community_lookup}__in': tower_communities})
                qs = qs.filter(q)
                if towers and self.tower_lookup and '__' in self.tower_lookup + self.community_lookup:
                    qs = qs.distinct()
        else:
            ids = community_ids_for(self.request.user, self.roles)
            if ids is not None:
                qs = qs.filter(**{f'{self.community_lookup}__in': ids})
        community = self.request.query_params.get('community')
        if community:
            qs = qs.filter(**{self.community_lookup: parse_uuid(community, 'community')})
        return qs

    def community_from(self, data, instance=None):
        """Community that the object being written belongs to. Override for indirect FKs."""
        return data.get('community') or getattr(instance, 'community', None)

    def tower_from(self, data, instance=None):
        """Tower that the object being written belongs to (None = community-wide)."""
        if not self.tower_lookup:
            return None
        if data.get('tower') is not None:
            return data['tower']
        if data.get('unit') is not None:
            return data['unit'].tower
        if instance is not None and self.tower_lookup in ('tower', 'unit__tower'):
            unit = getattr(instance, 'unit', None)
            return unit.tower if unit is not None else getattr(instance, 'tower', None)
        return None

    def assert_can_manage(self, community, tower=None):
        if community is None:
            raise ValidationError({'community': 'This field is required.'})
        if not has_community_role(self.request.user, community, self.roles):
            raise PermissionDenied('You do not manage this community.')
        if self.roles == MANAGER_ROLES and not can_manage_tower(self.request.user, community, tower, self.roles):
            raise PermissionDenied('You only manage some towers of this community.')

    def get_create_kwargs(self):
        return {}

    def perform_create(self, serializer):
        d = serializer.validated_data
        self.assert_can_manage(self.community_from(d), self.tower_from(d))
        serializer.save(**self.get_create_kwargs())

    def perform_update(self, serializer):
        d, inst = serializer.validated_data, serializer.instance
        self.assert_can_manage(self.community_from(d, inst), self.tower_from(d, inst))
        serializer.save()


class ManageViewSet(_CommunityRoleViewSetMixin, viewsets.ModelViewSet):
    permission_classes = [IsAuthenticated, IsCommunityManager]


class ManageReadOnlyViewSet(_CommunityRoleViewSetMixin, viewsets.ReadOnlyModelViewSet):
    permission_classes = [IsAuthenticated, IsCommunityManager]


class GuardViewSet(_CommunityRoleViewSetMixin, viewsets.GenericViewSet):
    permission_classes = [IsAuthenticated, IsGuard]
    roles = GUARD_ROLES
