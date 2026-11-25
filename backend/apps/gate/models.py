from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class VisitorType(models.TextChoices):
    GUEST = 'guest'
    DELIVERY = 'delivery'
    CAB = 'cab'
    SERVICE = 'service'
    OTHER = 'other'


class Visitor(BaseModel):
    """A visit to a unit: pre-approved by a resident, or a walk-in raised by the guard."""

    class Status(models.TextChoices):
        EXPECTED = 'expected', 'Pre-approved'
        WAITING = 'waiting', 'Waiting at gate'
        INSIDE = 'inside'
        EXITED = 'exited'
        DENIED = 'denied'
        LEFT_AT_GATE = 'left_at_gate', 'Left at gate'
        CANCELLED = 'cancelled'
        EXPIRED = 'expired'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='visitors')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='visitors')
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, blank=True)
    visitor_type = models.CharField(max_length=20, choices=VisitorType.choices, default=VisitorType.GUEST)
    company = models.CharField(max_length=100, blank=True)
    vehicle_no = models.CharField(max_length=30, blank=True)
    guests = models.PositiveSmallIntegerField(default=1)
    note = models.CharField(max_length=255, blank=True)
    photo = models.ImageField(upload_to='visitors/', null=True, blank=True)

    status = models.CharField(max_length=20, choices=Status.choices, default=Status.EXPECTED)
    pass_code = models.CharField(max_length=6, blank=True, db_index=True)
    expected_at = models.DateTimeField(null=True, blank=True)
    valid_until = models.DateTimeField(null=True, blank=True)
    is_walk_in = models.BooleanField(default=False)
    gate = models.ForeignKey('communities.Gate', on_delete=models.SET_NULL, null=True, blank=True)

    created_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='+'
    )
    responded_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='+'
    )
    responded_at = models.DateTimeField(null=True, blank=True)
    checked_in_at = models.DateTimeField(null=True, blank=True)
    checked_out_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['community', 'status'])]

    def __str__(self):
        return f'{self.name} -> {self.unit}'


class FrequentEntry(BaseModel):
    """Recurring access, e.g. milk delivery daily 6-7 AM."""

    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='frequent_entries')
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, blank=True)
    visitor_type = models.CharField(max_length=20, choices=VisitorType.choices, default=VisitorType.SERVICE)
    company = models.CharField(max_length=100, blank=True)
    valid_from = models.DateField()
    valid_until = models.DateField()
    days_of_week = models.JSONField(default=list, blank=True, help_text='0=Mon ... 6=Sun; empty = every day')
    time_from = models.TimeField(null=True, blank=True)
    time_to = models.TimeField(null=True, blank=True)
    pass_code = models.CharField(max_length=6, db_index=True)
    is_active = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['-created_at']
        verbose_name_plural = 'frequent entries'


class KidExitPermission(BaseModel):
    class Status(models.TextChoices):
        ACTIVE = 'active'
        USED = 'used'
        CANCELLED = 'cancelled'

    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='kid_exits')
    children = models.ManyToManyField('household.FamilyMember', related_name='exit_permissions')
    allowed_from = models.DateTimeField()
    allowed_until = models.DateTimeField()
    note = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['-created_at']


class SOSAlert(BaseModel):
    class Type(models.TextChoices):
        MEDICAL = 'medical'
        FIRE = 'fire'
        THEFT = 'theft', 'Theft / intruder'
        LIFT = 'lift', 'Stuck in lift'
        ANIMAL = 'animal', 'Animal threat'
        OTHER = 'other'

    class Status(models.TextChoices):
        ACTIVE = 'active'
        ACKNOWLEDGED = 'acknowledged'
        RESOLVED = 'resolved'
        CANCELLED = 'cancelled'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='sos_alerts')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='sos_alerts')
    raised_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    alert_type = models.CharField(max_length=20, choices=Type.choices)
    message = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.ACTIVE)
    handled_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='+'
    )
    acknowledged_at = models.DateTimeField(null=True, blank=True)
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        verbose_name = 'SOS alert'


class GuardShift(BaseModel):
    """A guard's duty session at a gate (shift selection screen)."""

    class Shift(models.TextChoices):
        MORNING = 'morning', 'Morning (6 AM – 2 PM)'
        EVENING = 'evening', 'Evening (2 PM – 10 PM)'
        NIGHT = 'night', 'Night (10 PM – 6 AM)'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='guard_shifts')
    guard = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='guard_shifts')
    gate = models.ForeignKey('communities.Gate', on_delete=models.SET_NULL, null=True, blank=True)
    shift = models.CharField(max_length=10, choices=Shift.choices)
    started_at = models.DateTimeField(auto_now_add=True)
    ended_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-started_at']


class VehicleLog(BaseModel):
    """Vehicle entry / exit recorded at the gate."""

    class Direction(models.TextChoices):
        IN = 'in'
        OUT = 'out'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='vehicle_logs')
    number = models.CharField(max_length=30)
    direction = models.CharField(max_length=3, choices=Direction.choices)
    vehicle = models.ForeignKey('household.Vehicle', on_delete=models.SET_NULL, null=True, blank=True)
    unit = models.ForeignKey('communities.Unit', on_delete=models.SET_NULL, null=True, blank=True)
    visitor = models.ForeignKey(Visitor, on_delete=models.SET_NULL, null=True, blank=True)
    note = models.CharField(max_length=150, blank=True)
    gate = models.ForeignKey('communities.Gate', on_delete=models.SET_NULL, null=True, blank=True)
    logged_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['-created_at']


class StaffAttendance(BaseModel):
    staff = models.ForeignKey('communities.StaffMember', on_delete=models.CASCADE, related_name='attendance')
    date = models.DateField()
    check_in = models.DateTimeField()
    check_out = models.DateTimeField(null=True, blank=True)
    marked_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['-check_in']


class Incident(BaseModel):
    class Severity(models.TextChoices):
        LOW = 'low'
        MEDIUM = 'medium'
        HIGH = 'high'
        CRITICAL = 'critical'

    class Status(models.TextChoices):
        OPEN = 'open'
        INVESTIGATING = 'investigating'
        RESOLVED = 'resolved'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='incidents')
    reported_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    title = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    category = models.CharField(max_length=40, default='General')
    severity = models.CharField(max_length=10, choices=Severity.choices, default=Severity.MEDIUM)
    location = models.CharField(max_length=120, blank=True)
    unit = models.ForeignKey('communities.Unit', on_delete=models.SET_NULL, null=True, blank=True)
    photo = models.ImageField(upload_to='incidents/', null=True, blank=True)
    status = models.CharField(max_length=15, choices=Status.choices, default=Status.OPEN)
    resolution = models.TextField(blank=True)

    class Meta:
        ordering = ['-created_at']


class GateEvent(BaseModel):
    """Audit log for IoT gate / boom barrier commands."""

    gate = models.ForeignKey('communities.Gate', on_delete=models.CASCADE, related_name='events')
    action = models.CharField(max_length=10, default='open')
    triggered_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    success = models.BooleanField(default=True)
    detail = models.CharField(max_length=200, blank=True)

    class Meta:
        ordering = ['-created_at']
