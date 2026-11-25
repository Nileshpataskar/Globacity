from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from apps.core.models import BaseModel


class FamilyMember(BaseModel):
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='family_members')
    name = models.CharField(max_length=150)
    relation = models.CharField(max_length=50)
    phone = models.CharField(max_length=20, blank=True)
    date_of_birth = models.DateField(null=True, blank=True)
    is_minor = models.BooleanField(default=False)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


class Vehicle(BaseModel):
    class Type(models.TextChoices):
        CAR = 'car'
        BIKE = 'bike'
        OTHER = 'other'

    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='vehicles')
    number = models.CharField(max_length=30)
    make_model = models.CharField(max_length=100, blank=True)
    color = models.CharField(max_length=30, blank=True)
    vehicle_type = models.CharField(max_length=10, choices=Type.choices, default=Type.CAR)
    parking_slot = models.CharField(max_length=30, blank=True)

    class Meta:
        ordering = ['number']

    def __str__(self):
        return self.number


class Pet(BaseModel):
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='pets')
    name = models.CharField(max_length=60)
    species = models.CharField(max_length=40)
    breed = models.CharField(max_length=60, blank=True)
    vaccinated = models.BooleanField(default=False)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


class DailyHelp(BaseModel):
    """Maid, driver, cook, nanny... One record per person per community; linked to many units."""

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='daily_help')
    name = models.CharField(max_length=150)
    phone = models.CharField(max_length=20)
    role = models.CharField(max_length=60)
    photo = models.ImageField(upload_to='daily-help/', null=True, blank=True)
    id_verified = models.BooleanField(default=False)
    pass_code = models.CharField(max_length=6, help_text='Code shown at the gate for entry')
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'daily help'
        constraints = [
            models.UniqueConstraint(fields=['community', 'phone'], name='unique_helper_phone'),
            models.UniqueConstraint(fields=['community', 'pass_code'], name='unique_helper_code'),
        ]

    def __str__(self):
        return f'{self.name} ({self.role})'


class DailyHelpAssignment(BaseModel):
    helper = models.ForeignKey(DailyHelp, on_delete=models.CASCADE, related_name='assignments')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='daily_help_assignments')
    timing = models.CharField(max_length=60, blank=True, help_text='e.g. 9:00 AM - 1:00 PM')
    added_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        constraints = [models.UniqueConstraint(fields=['helper', 'unit'], name='unique_helper_unit')]


class DailyHelpAttendance(BaseModel):
    helper = models.ForeignKey(DailyHelp, on_delete=models.CASCADE, related_name='attendance')
    date = models.DateField()
    check_in = models.DateTimeField()
    check_out = models.DateTimeField(null=True, blank=True)
    gate = models.ForeignKey('communities.Gate', on_delete=models.SET_NULL, null=True, blank=True)
    marked_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['-check_in']
        indexes = [models.Index(fields=['helper', 'date'])]


class DailyHelpReview(BaseModel):
    helper = models.ForeignKey(DailyHelp, on_delete=models.CASCADE, related_name='reviews')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='+')
    rating = models.PositiveSmallIntegerField(validators=[MinValueValidator(1), MaxValueValidator(5)])
    comment = models.TextField(blank=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [models.UniqueConstraint(fields=['helper', 'author'], name='one_review_per_author')]
