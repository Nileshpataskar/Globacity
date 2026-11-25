from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


def default_community_settings():
    return {
        'require_visitor_approval': True,
        'allow_classifieds': True,
        'allow_forum': True,
        'kid_exit_control': True,
    }


class Community(BaseModel):
    """A society / compound / building complex. Locale comes from ``city.country``."""

    city = models.ForeignKey('locations.City', on_delete=models.PROTECT, related_name='communities')
    name = models.CharField(max_length=150)
    slug = models.SlugField(max_length=160, unique=True)
    address = models.CharField(max_length=255, blank=True)
    latitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    longitude = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    contact_phone = models.CharField(max_length=20, blank=True)
    contact_email = models.EmailField(blank=True)
    timezone = models.CharField(max_length=64, blank=True, help_text='Overrides the city/country timezone')
    # White-label branding
    logo = models.ImageField(upload_to='community-logos/', null=True, blank=True)
    primary_color = models.CharField(max_length=9, default='#2563EB')
    secondary_color = models.CharField(max_length=9, default='#0EA5A4')
    settings = models.JSONField(default=default_community_settings, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        verbose_name_plural = 'communities'
        ordering = ['name']

    def __str__(self):
        return self.name

    @property
    def country(self):
        return self.city.country

    @property
    def currency(self):
        return self.city.country.currency

    @property
    def effective_timezone(self):
        return self.timezone or self.city.effective_timezone


class Tower(BaseModel):
    class ApprovalMode(models.TextChoices):
        MANUAL = 'manual', 'Tower / community admin approves'
        AUTO = 'auto', 'Approve automatically'

    community = models.ForeignKey(Community, on_delete=models.CASCADE, related_name='towers')
    name = models.CharField(max_length=100)
    code = models.CharField(max_length=20, blank=True)
    floors = models.PositiveSmallIntegerField(default=1)
    approval_mode = models.CharField(max_length=10, choices=ApprovalMode.choices, default=ApprovalMode.MANUAL,
                                     help_text='How resident join requests for this tower are approved')
    maintenance_amount = models.DecimalField(max_digits=12, decimal_places=3, null=True, blank=True,
                                             help_text='Default maintenance per flat; used when billing all flats')
    lifts = models.PositiveSmallIntegerField(null=True, blank=True)
    parking_slots = models.PositiveIntegerField(null=True, blank=True)
    contact_name = models.CharField(max_length=150, blank=True, help_text='Tower in-charge / contact person')
    contact_phone = models.CharField(max_length=20, blank=True)

    class Meta:
        ordering = ['name']
        constraints = [models.UniqueConstraint(fields=['community', 'name'], name='unique_tower_name')]

    def __str__(self):
        return f'{self.community.name} · {self.name}'


class Unit(BaseModel):
    class Type(models.TextChoices):
        APARTMENT = 'apartment'
        VILLA = 'villa'
        TOWNHOUSE = 'townhouse'
        OFFICE = 'office'
        SHOP = 'shop'

    tower = models.ForeignKey(Tower, on_delete=models.CASCADE, related_name='units')
    number = models.CharField(max_length=20)
    floor = models.SmallIntegerField(null=True, blank=True)
    unit_type = models.CharField(max_length=20, choices=Type.choices, default=Type.APARTMENT)
    bedrooms = models.PositiveSmallIntegerField(null=True, blank=True)
    area_sqft = models.PositiveIntegerField(null=True, blank=True)

    class Meta:
        ordering = ['tower__name', 'number']
        constraints = [models.UniqueConstraint(fields=['tower', 'number'], name='unique_unit_number')]

    def __str__(self):
        return f'{self.tower.name} · {self.number}'

    @property
    def community(self):
        return self.tower.community

    @property
    def label(self) -> str:
        return f'{self.tower.name} · {self.number}'


class Gate(BaseModel):
    community = models.ForeignKey(Community, on_delete=models.CASCADE, related_name='gates')
    name = models.CharField(max_length=100)
    is_active = models.BooleanField(default=True)
    iot_enabled = models.BooleanField(default=False, help_text='Boom barrier / gate controller connected')
    iot_device_id = models.CharField(max_length=100, blank=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return f'{self.community.name} · {self.name}'


class Membership(BaseModel):
    """A user's link to a unit (owner, tenant or family). Must be approved by management."""

    class Role(models.TextChoices):
        OWNER = 'owner'
        TENANT = 'tenant'
        FAMILY = 'family'

    class Status(models.TextChoices):
        PENDING = 'pending'
        APPROVED = 'approved'
        REJECTED = 'rejected'
        MOVED_OUT = 'moved_out'

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='memberships')
    unit = models.ForeignKey(Unit, on_delete=models.CASCADE, related_name='memberships')
    role = models.CharField(max_length=20, choices=Role.choices)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    note = models.CharField(max_length=255, blank=True)
    approved_by = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True, related_name='+'
    )
    approved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [models.UniqueConstraint(fields=['user', 'unit'], name='unique_membership')]

    def __str__(self):
        return f'{self.user} @ {self.unit} ({self.status})'


class StaffMember(BaseModel):
    """Community staff and roles. ``user`` is set for people who log in (admins, guards)."""

    class Role(models.TextChoices):
        ADMIN = 'admin', 'Community admin'
        MANAGER = 'manager', 'Facility / community manager'
        GUARD = 'guard', 'Security guard'
        COMMITTEE = 'committee', 'Committee member'
        FACILITY = 'facility', 'Facility staff'
        OTHER = 'other', 'Other'

    community = models.ForeignKey(Community, on_delete=models.CASCADE, related_name='staff')
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name='staff_roles'
    )
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20, blank=True)
    role = models.CharField(max_length=20, choices=Role.choices)
    designation = models.CharField(max_length=100, blank=True, help_text='e.g. Electrician, Supervisor')
    shift = models.CharField(max_length=50, blank=True)
    show_in_directory = models.BooleanField(default=True)
    is_active = models.BooleanField(default=True)
    towers = models.ManyToManyField(Tower, blank=True, related_name='staff',
                                    help_text='Limit this person to these towers. Empty = whole community.')

    class Meta:
        ordering = ['name']
        constraints = [
            models.UniqueConstraint(
                fields=['community', 'user', 'role'], condition=models.Q(user__isnull=False), name='unique_staff_role'
            ),
        ]

    def __str__(self):
        return f'{self.name} ({self.get_role_display()})'


class EmergencyContact(BaseModel):
    class Group(models.TextChoices):
        COMMUNITY = 'community'
        PERSONAL = 'personal'

    community = models.ForeignKey(Community, on_delete=models.CASCADE, null=True, blank=True, related_name='emergency_contacts')
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.CASCADE, null=True, blank=True, related_name='emergency_contacts'
    )
    name = models.CharField(max_length=100)
    phone = models.CharField(max_length=20)
    group = models.CharField(max_length=20, choices=Group.choices, default=Group.COMMUNITY)
    icon = models.CharField(max_length=40, blank=True, help_text='Icon name hint for the app')
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ['order', 'name']

    def __str__(self):
        return self.name
