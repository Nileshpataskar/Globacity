from django.conf import settings
from django.db import models

from apps.core.models import BaseModel


class Notice(BaseModel):
    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='notices')
    title = models.CharField(max_length=200)
    body = models.TextField()
    category = models.CharField(max_length=40, default='General')
    is_pinned = models.BooleanField(default=False)
    attachment = models.FileField(upload_to='notices/', null=True, blank=True)
    target_towers = models.ManyToManyField('communities.Tower', blank=True, help_text='Empty = whole community')
    published_at = models.DateTimeField()
    expires_at = models.DateTimeField(null=True, blank=True)
    posted_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')
    author_label = models.CharField(max_length=100, default='Management', help_text='Shown as the sender')

    class Meta:
        ordering = ['-is_pinned', '-published_at']

    def __str__(self):
        return self.title


class Poll(BaseModel):
    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='polls')
    question = models.CharField(max_length=255)
    description = models.TextField(blank=True)
    closes_at = models.DateTimeField()
    one_vote_per_unit = models.BooleanField(default=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.question


class PollOption(models.Model):
    poll = models.ForeignKey(Poll, on_delete=models.CASCADE, related_name='options')
    label = models.CharField(max_length=150)
    order = models.PositiveSmallIntegerField(default=0)

    class Meta:
        ordering = ['order', 'id']

    def __str__(self):
        return self.label


class PollVote(BaseModel):
    poll = models.ForeignKey(Poll, on_delete=models.CASCADE, related_name='votes')
    option = models.ForeignKey(PollOption, on_delete=models.CASCADE, related_name='votes')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='+')

    class Meta:
        constraints = [models.UniqueConstraint(fields=['poll', 'user'], name='one_vote_per_user')]


class Event(BaseModel):
    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='events')
    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    category = models.CharField(max_length=40, default='Community')
    venue = models.CharField(max_length=150)
    starts_at = models.DateTimeField()
    ends_at = models.DateTimeField(null=True, blank=True)
    capacity = models.PositiveIntegerField(null=True, blank=True)
    cover = models.ImageField(upload_to='events/', null=True, blank=True)
    created_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, related_name='+')

    class Meta:
        ordering = ['starts_at']

    def __str__(self):
        return self.title


class EventRSVP(BaseModel):
    event = models.ForeignKey(Event, on_delete=models.CASCADE, related_name='rsvps')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='+')
    guests = models.PositiveSmallIntegerField(default=1)

    class Meta:
        verbose_name = 'event RSVP'
        constraints = [models.UniqueConstraint(fields=['event', 'user'], name='one_rsvp_per_user')]


class ForumPost(BaseModel):
    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='forum_posts')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='+')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='forum_posts')
    title = models.CharField(max_length=200)
    body = models.TextField(blank=True)
    tag = models.CharField(max_length=40, default='General')
    is_locked = models.BooleanField(default=False)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.title


class ForumReply(BaseModel):
    post = models.ForeignKey(ForumPost, on_delete=models.CASCADE, related_name='replies')
    author = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    body = models.TextField()

    class Meta:
        ordering = ['created_at']
        verbose_name_plural = 'forum replies'


class ForumLike(models.Model):
    post = models.ForeignKey(ForumPost, on_delete=models.CASCADE, related_name='likes')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')

    class Meta:
        constraints = [models.UniqueConstraint(fields=['post', 'user'], name='one_like_per_user')]


class Classified(BaseModel):
    class Status(models.TextChoices):
        ACTIVE = 'active'
        SOLD = 'sold'
        REMOVED = 'removed'

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='classifieds')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='+')
    seller = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='classifieds')
    title = models.CharField(max_length=150)
    description = models.TextField(blank=True)
    category = models.CharField(max_length=40, default='Other')
    price = models.DecimalField(max_digits=12, decimal_places=3)
    currency = models.ForeignKey('locations.Currency', on_delete=models.PROTECT)
    image = models.ImageField(upload_to='classifieds/', null=True, blank=True)
    status = models.CharField(max_length=10, choices=Status.choices, default=Status.ACTIVE)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return self.title


class ServiceVendor(BaseModel):
    """Home store / local services listed for a community."""

    community = models.ForeignKey('communities.Community', on_delete=models.CASCADE, related_name='vendors')
    name = models.CharField(max_length=150)
    category = models.CharField(max_length=60)
    description = models.TextField(blank=True)
    phone = models.CharField(max_length=20, blank=True)
    price_from = models.DecimalField(max_digits=12, decimal_places=3, default=0)
    currency = models.ForeignKey('locations.Currency', on_delete=models.PROTECT)
    eta_text = models.CharField(max_length=40, blank=True, help_text='e.g. Today, 2 hrs')
    logo = models.ImageField(upload_to='vendors/', null=True, blank=True)
    is_active = models.BooleanField(default=True)

    class Meta:
        ordering = ['name']

    def __str__(self):
        return self.name


class ServiceBooking(BaseModel):
    class Status(models.TextChoices):
        REQUESTED = 'requested'
        CONFIRMED = 'confirmed'
        COMPLETED = 'completed'
        CANCELLED = 'cancelled'

    vendor = models.ForeignKey(ServiceVendor, on_delete=models.CASCADE, related_name='bookings')
    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='service_bookings')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    slot_start = models.DateTimeField()
    notes = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.REQUESTED)
    rating = models.PositiveSmallIntegerField(null=True, blank=True)

    class Meta:
        ordering = ['-slot_start']


class MoveRequest(BaseModel):
    class Type(models.TextChoices):
        MOVE_IN = 'move_in'
        MOVE_OUT = 'move_out'

    class Status(models.TextChoices):
        PENDING = 'pending'
        APPROVED = 'approved'
        REJECTED = 'rejected'
        COMPLETED = 'completed'
        CANCELLED = 'cancelled'

    unit = models.ForeignKey('communities.Unit', on_delete=models.CASCADE, related_name='move_requests')
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='+')
    move_type = models.CharField(max_length=10, choices=Type.choices)
    move_date = models.DateField()
    moving_company = models.CharField(max_length=150, blank=True)
    service_lift = models.BooleanField(default=True)
    notes = models.CharField(max_length=255, blank=True)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    reviewed_by = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True,
                                    related_name='+')
    review_note = models.CharField(max_length=255, blank=True)

    class Meta:
        ordering = ['-created_at']


class MoveDocument(BaseModel):
    request = models.ForeignKey(MoveRequest, on_delete=models.CASCADE, related_name='documents')
    doc_type = models.CharField(max_length=60, help_text='e.g. Emirates ID, Tenancy contract')
    file = models.FileField(upload_to='move-documents/')
