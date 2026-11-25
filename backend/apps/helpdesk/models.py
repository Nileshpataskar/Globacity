from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

from apps.core.models import BaseModel


class TicketCategory(BaseModel):
    """``community`` empty = default category available everywhere."""

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, null=True, blank=True,
                                  related_name='ticket_categories')
    name = models.CharField(max_length=60)
    icon = models.CharField(max_length=40, blank=True)
    sla_hours = models.PositiveIntegerField(default=48)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['name']
        verbose_name_plural = 'ticket categories'

    def __str__(self):
        return self.name


class Ticket(BaseModel):
    class Priority(models.TextChoices):
        LOW = 'low'
        MEDIUM = 'medium'
        HIGH = 'high'
        URGENT = 'urgent'

    class Status(models.TextChoices):
        OPEN = 'open'
        IN_PROGRESS = 'in_progress'
        ON_HOLD = 'on_hold'
        RESOLVED = 'resolved'
        CLOSED = 'closed'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='tickets')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='tickets')
    raised_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='tickets')
    category = models.ForeignKey(TicketCategory, on_delete=models.PROTECT, related_name='tickets')
    number = models.CharField(max_length=20)
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    priority = models.CharField(max_length=10, choices=Priority.choices, default=Priority.MEDIUM)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.OPEN)
    assigned_to = models.ForeignKey('communities.StaffMember', on_delete=models.SET_NULL, null=True, blank=True,
                                    related_name='tickets')
    resolved_at = models.DateTimeField(null=True, blank=True)
    rating = models.PositiveSmallIntegerField(null=True, blank=True,
                                              validators=[MinValueValidator(1), MaxValueValidator(5)])
    rating_comment = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ['-created_at']
        constraints = [models.UniqueConstraint(fields=['community', 'number'], name='unique_ticket_number')]

    def __str__(self):
        return f'{self.number} · {self.title}'


class TicketUpdate(BaseModel):
    ticket = models.ForeignKey(Ticket, on_delete=models.CASCADE, related_name='updates')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    message = models.TextField()
    status_change = models.CharField(max_length=20, blank=True)
    is_internal = models.BooleanField(default=False, help_text='Visible to staff only')

    class Meta:
        ordering = ['created_at']


class TicketAttachment(BaseModel):
    ticket = models.ForeignKey(Ticket, on_delete=models.CASCADE, related_name='attachments')
    file = models.FileField(upload_to='tickets/')
    uploaded_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
