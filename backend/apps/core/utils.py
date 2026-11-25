import secrets
from zoneinfo import ZoneInfo

from django.utils import timezone


def generate_code(exists, length=6, attempts=20):
    """Random numeric code for which ``exists(code)`` is False."""
    for _ in range(attempts):
        code = f'{secrets.randbelow(10 ** length):0{length}d}'
        if not exists(code):
            return code
    raise RuntimeError('Could not generate a unique code')


def community_today(community):
    """Today's date in the community's local timezone."""
    return timezone.localdate(timezone=ZoneInfo(community.effective_timezone))


def community_now(community):
    return timezone.localtime(timezone=ZoneInfo(community.effective_timezone))
