from dataclasses import dataclass
from datetime import timedelta

from django.db.models import Q
from django.utils import timezone

from apps.core.utils import community_now, generate_code
from apps.household.models import DailyHelp

from .models import FrequentEntry, Visitor

EARLY_ENTRY_MINUTES = 120


def code_in_use(community, code):
    return (
        Visitor.objects.filter(community=community, pass_code=code, status=Visitor.Status.EXPECTED).exists()
        or FrequentEntry.objects.filter(unit__tower__community=community, pass_code=code, is_active=True).exists()
        or DailyHelp.objects.filter(community=community, pass_code=code).exists()
    )


def new_pass_code(community):
    return generate_code(lambda c: code_in_use(community, c))


def expire_stale_visitors(qs=None):
    qs = qs if qs is not None else Visitor.objects.all()
    qs.filter(status=Visitor.Status.EXPECTED, valid_until__lt=timezone.now()).update(status=Visitor.Status.EXPIRED)


@dataclass
class CodeMatch:
    kind: str
    obj: object
    community: object
    allowed: bool
    reason: str = ''

    def as_dict(self):
        if self.kind == 'daily_help':
            units = [a.unit.label for a in self.obj.assignments.select_related('unit__tower')]
            detail = self.obj.role
        else:
            units = [self.obj.unit.label]
            detail = self.obj.company or self.obj.get_visitor_type_display()
        return {'kind': self.kind, 'id': self.obj.pk, 'name': self.obj.name, 'detail': detail, 'units': units,
                'allowed': self.allowed, 'reason': self.reason}


def frequent_entry_allowed(entry, community):
    now = community_now(community)
    if not (entry.valid_from <= now.date() <= entry.valid_until):
        return False, 'Outside the valid date range.'
    if entry.days_of_week and now.weekday() not in entry.days_of_week:
        return False, 'Not allowed on this day.'
    if entry.time_from and entry.time_to and not (entry.time_from <= now.time() <= entry.time_to):
        return False, f'Allowed only between {entry.time_from:%H:%M} and {entry.time_to:%H:%M}.'
    return True, ''


def resolve_code(code, community_ids):
    """Find what a 6-digit gate code belongs to, within the guard's communities (None = all)."""
    scope = Q() if community_ids is None else Q(community_id__in=community_ids)

    expire_stale_visitors(Visitor.objects.filter(pass_code=code))
    visitor = (Visitor.objects.filter(scope, pass_code=code, status=Visitor.Status.EXPECTED)
               .select_related('unit__tower', 'community__city__country').first())
    if visitor:
        early = visitor.expected_at and timezone.now() < visitor.expected_at - timedelta(minutes=EARLY_ENTRY_MINUTES)
        return CodeMatch('visitor', visitor, visitor.community, not early, 'Too early for this pass.' if early else '')

    entry_scope = Q() if community_ids is None else Q(unit__tower__community_id__in=community_ids)
    entry = (FrequentEntry.objects.filter(entry_scope, pass_code=code, is_active=True)
             .select_related('unit__tower__community__city__country').first())
    if entry:
        community = entry.unit.tower.community
        allowed, reason = frequent_entry_allowed(entry, community)
        return CodeMatch('frequent_entry', entry, community, allowed, reason)

    helper = DailyHelp.objects.filter(scope, pass_code=code).select_related('community__city__country').first()
    if helper:
        allowed = helper.is_active and helper.assignments.exists()
        return CodeMatch('daily_help', helper, helper.community, allowed, '' if allowed else 'Not working for any unit.')
    return None
