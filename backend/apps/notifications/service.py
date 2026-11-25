"""Single entry point for notifying users: stores the notification and pushes it over WebSocket."""

import logging

from asgiref.sync import async_to_sync
from channels.layers import get_channel_layer

from .models import Notification

logger = logging.getLogger('apps.notifications')


def user_group(user_id) -> str:
    return f'user_{user_id}'


def notify(users, title, body='', category=Notification.Category.GENERAL, data=None, pref=None):
    """Notify ``users`` (iterable of User). ``pref`` is an optional notification-preference key to respect."""
    from apps.accounts.models import UserSettings

    users = [u for u in users if u is not None]
    if pref:
        muted = set(
            UserSettings.objects.filter(user__in=users, **{f'notification_prefs__{pref}': False})
            .values_list('user_id', flat=True)
        )
        users = [u for u in users if u.pk not in muted]
    if not users:
        return []

    data = {k: str(v) for k, v in (data or {}).items()}
    created = Notification.objects.bulk_create(
        [Notification(user=u, title=title, body=body, category=category, data=data) for u in users]
    )

    layer = get_channel_layer()
    for n in created:
        try:
            async_to_sync(layer.group_send)(
                user_group(n.user_id),
                {
                    'type': 'notify',
                    'payload': {
                        'id': str(n.id), 'title': n.title, 'body': n.body, 'category': n.category,
                        'data': n.data, 'created_at': n.created_at.isoformat(),
                    },
                },
            )
        except Exception:  # Realtime delivery must never break the request.
            logger.exception('WebSocket push failed')
    return created


def notify_unit(unit, title, body='', category=Notification.Category.GENERAL, data=None, pref=None, exclude=None):
    """Notify every approved resident of a unit."""
    from apps.communities.models import Membership

    users = [
        m.user for m in Membership.objects.filter(unit=unit, status=Membership.Status.APPROVED).select_related('user')
        if m.user != exclude
    ]
    return notify(users, title, body, category, data, pref)


def notify_community_staff(community, roles, title, body='', category=Notification.Category.GENERAL, data=None,
                           tower=None):
    """Notify staff with ``roles``. With ``tower``, tower-limited staff are included only for that tower."""
    from django.db.models import Count, Q

    from apps.communities.models import StaffMember

    staff = (StaffMember.objects.filter(community=community, role__in=roles, is_active=True, user__isnull=False)
             .annotate(n_towers=Count('towers')))
    scope = Q(n_towers=0)
    if tower is not None:
        scope |= Q(towers=tower)
    users = {s.user_id: s.user for s in staff.filter(scope).select_related('user')}
    return notify(list(users.values()), title, body, category, data)


def notify_community_residents(community, title, body='', category=Notification.Category.COMMUNITY, data=None,
                               pref=None, towers=None):
    """Notify every approved resident of a community (optionally only some towers)."""
    from apps.accounts.models import User
    from apps.communities.models import Membership

    members = Membership.objects.filter(unit__tower__community=community, status=Membership.Status.APPROVED)
    if towers:
        members = members.filter(unit__tower__in=towers)
    users = User.objects.filter(pk__in=members.values('user_id'))
    return notify(list(users), title, body, category, data, pref)
