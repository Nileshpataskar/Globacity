"""Role model.

* Platform admin   -> ``user.is_staff``; manages countries, cities, communities.
* Community roles  -> ``communities.StaffMember`` (admin, manager, guard, ...).
* Resident         -> approved ``communities.Membership`` on a unit.
"""

from rest_framework.permissions import BasePermission

MANAGER_ROLES = ('admin', 'manager')
GUARD_ROLES = ('guard', 'admin', 'manager')


def is_platform_admin(user):
    return bool(user and user.is_authenticated and user.is_staff)


def community_ids_for(user, roles):
    """Community ids where ``user`` holds one of ``roles``. ``None`` means all communities."""
    if is_platform_admin(user):
        return None
    from apps.communities.models import StaffMember

    return list(
        StaffMember.objects.filter(user=user, is_active=True, role__in=roles).values_list('community_id', flat=True)
    )


def has_community_role(user, community, roles):
    ids = community_ids_for(user, roles)
    return ids is None or community.pk in ids


def manager_scope(user, roles=MANAGER_ROLES):
    """Where ``user`` may manage: ``(full_community_ids, tower_ids)``.

    ``full_community_ids`` is ``None`` for a platform admin (everything). A staff role with towers selected
    only covers those towers; a role without towers covers the whole community.
    """
    if is_platform_admin(user):
        return None, set()
    from apps.communities.models import StaffMember

    full, towers = set(), set()
    staff = StaffMember.objects.filter(user=user, is_active=True, role__in=roles).prefetch_related('towers')
    for s in staff:
        tower_ids = {t.pk for t in s.towers.all()}
        if tower_ids:
            towers |= tower_ids
        else:
            full.add(s.community_id)
    return full, towers


def can_manage_tower(user, community, tower, roles=MANAGER_ROLES):
    """True if ``user`` manages the whole ``community``, or ``tower`` (when given) is one of theirs."""
    full, towers = manager_scope(user, roles)
    if full is None or community.pk in full:
        return True
    return tower is not None and tower.pk in towers


class IsPlatformAdmin(BasePermission):
    message = 'Platform administrator access required.'

    def has_permission(self, request, view):
        return is_platform_admin(request.user)


class _HasAnyCommunityRole(BasePermission):
    roles = ()

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        ids = community_ids_for(request.user, self.roles)
        return ids is None or len(ids) > 0


class IsCommunityManager(_HasAnyCommunityRole):
    message = 'Community admin or manager access required.'
    roles = MANAGER_ROLES


class IsGuard(_HasAnyCommunityRole):
    message = 'Security guard access required.'
    roles = GUARD_ROLES


class IsUnitMember(BasePermission):
    """Resolves the unit from ``X-Unit-ID``; the view raises a clear error if it can't."""

    def has_permission(self, request, view):
        if not (request.user and request.user.is_authenticated):
            return False
        return view.get_membership() is not None
