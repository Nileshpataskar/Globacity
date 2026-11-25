from datetime import timedelta

from django.db import IntegrityError, transaction
from django.db.models import Avg, Count, Exists, OuterRef, Prefetch, Q, Subquery, Sum
from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, status
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.response import Response

from apps.core.permissions import MANAGER_ROLES, has_community_role, manager_scope
from apps.core.scoping import (
    ManageReadOnlyViewSet,
    ManageViewSet,
    UnitScopedCreateListViewSet,
    UnitScopedReadOnlyViewSet,
    UnitScopedViewSet,
)
from apps.notifications.models import Notification
from apps.notifications.service import notify, notify_community_residents, notify_community_staff, notify_unit

from .models import (
    Classified,
    Event,
    EventRSVP,
    ForumLike,
    ForumPost,
    ForumReply,
    MoveRequest,
    Notice,
    Poll,
    PollOption,
    PollVote,
    ServiceBooking,
    ServiceVendor,
)
from .serializers import (
    BookingSerializer,
    BookingStatusSerializer,
    ClassifiedSerializer,
    EventSerializer,
    ForumPostSerializer,
    ForumReplySerializer,
    ManageEventSerializer,
    ManageNoticeSerializer,
    ManagePollSerializer,
    ManageVendorSerializer,
    MoveDocumentSerializer,
    MoveRequestSerializer,
    NoticeSerializer,
    PollSerializer,
    RatingSerializer,
    ReviewNoteSerializer,
    RSVPSerializer,
    VendorSerializer,
    VoteSerializer,
)

CAT = Notification.Category


def polls_queryset():
    return Poll.objects.prefetch_related(
        Prefetch('options', queryset=PollOption.objects.annotate(vote_count=Count('votes')))
    )


def events_queryset(user):
    mine = EventRSVP.objects.filter(event=OuterRef('pk'), user=user)
    return Event.objects.annotate(
        attendees=Sum('rsvps__guests', default=0),
        my_guests=Subquery(mine.values('guests')[:1]),
    )


def vendors_queryset():
    return ServiceVendor.objects.annotate(rating=Avg('bookings__rating'))


# ---------------------------------------------------------------------------
# Residents
# ---------------------------------------------------------------------------


class NoticeViewSet(UnitScopedReadOnlyViewSet):
    serializer_class = NoticeSerializer
    queryset = Notice.objects.all()
    scope = 'community'
    filterset_fields = ['category', 'is_pinned']
    search_fields = ['title', 'body']

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, 'swagger_fake_view', False):
            return qs
        now = timezone.now()
        return qs.filter(
            Q(published_at__lte=now), Q(expires_at__isnull=True) | Q(expires_at__gt=now),
            Q(target_towers__isnull=True) | Q(target_towers=self.unit.tower),
        ).distinct()


class PollViewSet(UnitScopedReadOnlyViewSet):
    serializer_class = PollSerializer
    queryset = Poll.objects.all()
    scope = 'community'

    def get_queryset(self):
        qs = super().get_queryset()
        return polls_queryset().filter(pk__in=qs.values('pk'))

    def get_serializer_context(self):
        ctx = super().get_serializer_context()
        if not getattr(self, 'swagger_fake_view', False) and self.request.user.is_authenticated:
            ctx['unit'] = self.unit
        return ctx

    @extend_schema(request=VoteSerializer, responses=PollSerializer)
    @action(detail=True, methods=['post'])
    def vote(self, request, pk=None):
        poll = self.get_object()
        s = VoteSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        if poll.closes_at <= timezone.now():
            raise ValidationError({'detail': 'This poll is closed.'})
        option = poll.options.filter(pk=s.validated_data['option']).first()
        if option is None:
            raise ValidationError({'option': 'Not an option of this poll.'})
        if poll.one_vote_per_unit and PollVote.objects.filter(poll=poll, unit=self.unit).exists():
            raise ValidationError({'detail': 'Your unit has already voted.'})
        try:
            PollVote.objects.create(poll=poll, option=option, user=request.user, unit=self.unit)
        except IntegrityError:
            raise ValidationError({'detail': 'You have already voted.'})
        return Response(self.get_serializer(self.get_queryset().get(pk=poll.pk)).data)


class EventViewSet(UnitScopedReadOnlyViewSet):
    """Upcoming events (``?past=true`` for past ones)."""

    serializer_class = EventSerializer
    queryset = Event.objects.all()
    scope = 'community'
    filterset_fields = ['category']

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, 'swagger_fake_view', False):
            return qs
        qs = events_queryset(self.request.user).filter(pk__in=qs.values('pk'))
        cutoff = timezone.now() - timedelta(hours=6)
        if self.request.query_params.get('past') == 'true':
            return qs.filter(starts_at__lt=cutoff).order_by('-starts_at')
        return qs.filter(starts_at__gte=cutoff)

    @extend_schema(parameters=[OpenApiParameter('past', bool)])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    @extend_schema(request=RSVPSerializer, responses=EventSerializer)
    @action(detail=True, methods=['post'])
    def rsvp(self, request, pk=None):
        event = self.get_object()
        s = RSVPSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        EventRSVP.objects.filter(event=event, user=request.user).delete()
        if s.validated_data['going']:
            if event.capacity and (event.attendees + s.validated_data['guests']) > event.capacity:
                raise ValidationError({'detail': 'The event is full.'})
            EventRSVP.objects.create(event=event, user=request.user, unit=self.unit, guests=s.validated_data['guests'])
        return Response(self.get_serializer(self.get_queryset().get(pk=event.pk)).data)


class AuthorOwnedMixin:
    owner_field = 'author'

    def _check_owner(self, instance):
        if getattr(instance, f'{self.owner_field}_id') != self.request.user.pk:
            raise PermissionDenied('Only the author can change this.')

    def perform_update(self, serializer):
        self._check_owner(serializer.instance)
        serializer.save()

    def perform_destroy(self, instance):
        self._check_owner(instance)
        instance.delete()


class ForumPostViewSet(AuthorOwnedMixin, UnitScopedViewSet):
    serializer_class = ForumPostSerializer
    queryset = ForumPost.objects.select_related('author', 'unit__tower')
    scope = 'community'
    filterset_fields = ['tag']
    search_fields = ['title', 'body']

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, 'swagger_fake_view', False):
            return qs
        liked = ForumLike.objects.filter(post=OuterRef('pk'), user=self.request.user)
        return qs.annotate(likes_count=Count('likes', distinct=True), replies_count=Count('replies', distinct=True),
                           liked=Exists(liked))

    def perform_create(self, serializer):
        if not self.community.settings.get('allow_forum', True):
            raise PermissionDenied('The forum is disabled in this community.')
        serializer.save(community=self.community, unit=self.unit, author=self.request.user)

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        self.perform_create(s)
        return Response(self.get_serializer(self.get_queryset().get(pk=s.instance.pk)).data, status=201)

    @extend_schema(methods=['get'], responses=ForumReplySerializer(many=True))
    @extend_schema(methods=['post'], request=ForumReplySerializer, responses=ForumReplySerializer)
    @action(detail=True, methods=['get', 'post'])
    def replies(self, request, pk=None):
        post = self.get_object()
        if request.method == 'GET':
            return Response(ForumReplySerializer(post.replies.select_related('author'), many=True).data)
        if post.is_locked:
            raise ValidationError({'detail': 'This discussion is locked.'})
        s = ForumReplySerializer(data=request.data)
        s.is_valid(raise_exception=True)
        reply = s.save(post=post, author=request.user)
        if post.author_id != request.user.pk:
            notify([post.author], 'New reply to your post', post.title, CAT.COMMUNITY, {'post_id': post.id},
                   pref='forum_replies')
        return Response(ForumReplySerializer(reply).data, status=201)

    @extend_schema(request=None, responses=ForumPostSerializer)
    @action(detail=True, methods=['post'])
    def like(self, request, pk=None):
        """Toggle like."""
        post = self.get_object()
        deleted, _ = ForumLike.objects.filter(post=post, user=request.user).delete()
        if not deleted:
            ForumLike.objects.create(post=post, user=request.user)
        return Response(self.get_serializer(self.get_queryset().get(pk=post.pk)).data)


class ClassifiedViewSet(AuthorOwnedMixin, UnitScopedViewSet):
    """Buy & sell within the community. ``?mine=true`` lists your own ads including sold ones."""

    serializer_class = ClassifiedSerializer
    queryset = Classified.objects.select_related('seller', 'unit__tower')
    scope = 'community'
    owner_field = 'seller'
    filterset_fields = ['category']
    search_fields = ['title', 'description']
    parser_classes = [JSONParser, MultiPartParser, FormParser]

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, 'swagger_fake_view', False):
            return qs
        if self.request.query_params.get('mine') == 'true':
            return qs.filter(seller=self.request.user).exclude(status=Classified.Status.REMOVED)
        if self.action == 'list':
            return qs.filter(status=Classified.Status.ACTIVE)
        return qs.exclude(status=Classified.Status.REMOVED)

    @extend_schema(parameters=[OpenApiParameter('mine', bool)])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def perform_create(self, serializer):
        if not self.community.settings.get('allow_classifieds', True):
            raise PermissionDenied('Classifieds are disabled in this community.')
        serializer.save(community=self.community, unit=self.unit, seller=self.request.user,
                        currency=self.community.currency)

    @extend_schema(request=None, responses=ClassifiedSerializer)
    @action(detail=True, methods=['post'], url_path='mark-sold')
    def mark_sold(self, request, pk=None):
        item = self.get_object()
        self._check_owner(item)
        item.status = Classified.Status.SOLD
        item.save(update_fields=['status'])
        return Response(ClassifiedSerializer(item).data)


class VendorViewSet(UnitScopedReadOnlyViewSet):
    serializer_class = VendorSerializer
    queryset = ServiceVendor.objects.filter(is_active=True)
    scope = 'community'
    filterset_fields = ['category']
    search_fields = ['name', 'category']

    def get_queryset(self):
        return vendors_queryset().filter(pk__in=super().get_queryset().values('pk'))


class BookingViewSet(UnitScopedCreateListViewSet):
    serializer_class = BookingSerializer
    queryset = ServiceBooking.objects.select_related('vendor', 'unit__tower')
    filterset_fields = ['status']

    def perform_create(self, serializer):
        vendor = serializer.validated_data['vendor']
        if vendor.community_id != self.community.pk or not vendor.is_active:
            raise ValidationError({'vendor': 'Vendor is not available in your community.'})
        serializer.save(unit=self.unit, user=self.request.user)

    @extend_schema(request=None, responses=BookingSerializer)
    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        b = self.get_object()
        if b.status in (ServiceBooking.Status.COMPLETED, ServiceBooking.Status.CANCELLED):
            raise ValidationError({'detail': 'Booking is already closed.'})
        b.status = ServiceBooking.Status.CANCELLED
        b.save(update_fields=['status'])
        return Response(BookingSerializer(b).data)

    @extend_schema(request=RatingSerializer, responses=BookingSerializer)
    @action(detail=True, methods=['post'])
    def rate(self, request, pk=None):
        b = self.get_object()
        if b.status != ServiceBooking.Status.COMPLETED:
            raise ValidationError({'detail': 'You can rate completed bookings only.'})
        s = RatingSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        b.rating = s.validated_data['rating']
        b.save(update_fields=['rating'])
        return Response(BookingSerializer(b).data)


class MoveRequestViewSet(UnitScopedCreateListViewSet):
    serializer_class = MoveRequestSerializer
    queryset = MoveRequest.objects.select_related('unit__tower', 'user').prefetch_related('documents')
    filterset_fields = ['status', 'move_type']

    def perform_create(self, serializer):
        m = serializer.save(unit=self.unit, user=self.request.user)
        notify_community_staff(self.community, MANAGER_ROLES, f'New {m.get_move_type_display()} request',
                               f'{self.unit.label} on {m.move_date}', CAT.COMMUNITY, {'move_request_id': m.id})

    @extend_schema(request={'multipart/form-data': MoveDocumentSerializer}, responses=MoveDocumentSerializer)
    @action(detail=True, methods=['post'], parser_classes=[MultiPartParser, FormParser])
    def documents(self, request, pk=None):
        m = self.get_object()
        s = MoveDocumentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        s.save(request=m)
        return Response(s.data, status=201)

    @extend_schema(request=None, responses=MoveRequestSerializer)
    @action(detail=True, methods=['post'])
    def cancel(self, request, pk=None):
        m = self.get_object()
        if m.status != MoveRequest.Status.PENDING:
            raise ValidationError({'detail': 'Only pending requests can be cancelled.'})
        m.status = MoveRequest.Status.CANCELLED
        m.save(update_fields=['status'])
        return Response(MoveRequestSerializer(m).data)


# ---------------------------------------------------------------------------
# Management
# ---------------------------------------------------------------------------


class ManageNoticeViewSet(ManageViewSet):
    serializer_class = ManageNoticeSerializer
    queryset = Notice.objects.prefetch_related('target_towers')
    filterset_fields = ['community', 'category', 'is_pinned']
    search_fields = ['title', 'body']
    tower_lookup = 'target_towers'
    readable_by_tower_admins = True

    def _assert_towers(self, community, targets):
        """Tower admins must address a notice to one or more of their own towers."""
        full, mine = manager_scope(self.request.user)
        if full is None or (community and community.pk in full):
            return
        if not targets or any(t.pk not in mine for t in targets):
            raise PermissionDenied('Choose only your own tower(s) under "Only for towers".')

    def perform_create(self, serializer):
        community = serializer.validated_data.get('community')
        if community is None:
            raise ValidationError({'community': 'This field is required.'})
        if not has_community_role(self.request.user, community, MANAGER_ROLES):
            raise PermissionDenied('You do not manage this community.')
        self._assert_towers(community, serializer.validated_data.get('target_towers'))
        send = serializer.validated_data.pop('notify', True)
        notice = serializer.save(posted_by=self.request.user,
                                 published_at=serializer.validated_data.get('published_at') or timezone.now())
        if send:
            notify_community_residents(notice.community, notice.title, notice.body[:140], CAT.NOTICE,
                                       {'notice_id': notice.id}, pref='notices',
                                       towers=list(notice.target_towers.all()))

    def perform_update(self, serializer):
        serializer.validated_data.pop('notify', None)
        inst = serializer.instance
        self._assert_towers(inst.community, serializer.validated_data.get('target_towers', list(inst.target_towers.all())))
        serializer.save()

    def perform_destroy(self, instance):
        self._assert_towers(instance.community, list(instance.target_towers.all()))
        instance.delete()


class ManagePollViewSet(ManageViewSet):
    serializer_class = ManagePollSerializer
    queryset = Poll.objects.all()
    filterset_fields = ['community']

    def get_queryset(self):
        return polls_queryset().filter(pk__in=super().get_queryset().values('pk'))

    @transaction.atomic
    def perform_create(self, serializer):
        self.assert_can_manage(serializer.validated_data.get('community'))
        labels = serializer.validated_data.pop('option_labels')
        poll = serializer.save(created_by=self.request.user)
        PollOption.objects.bulk_create([PollOption(poll=poll, label=label, order=i) for i, label in enumerate(labels)])
        transaction.on_commit(lambda: notify_community_residents(
            poll.community, 'New poll', poll.question, CAT.COMMUNITY, {'poll_id': poll.id}, pref='polls_events'))

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        self.perform_create(s)
        return Response(self.get_serializer(self.get_queryset().get(pk=s.instance.pk)).data, status=201)

    def perform_update(self, serializer):
        serializer.validated_data.pop('option_labels', None)
        super().perform_update(serializer)


class ManageEventViewSet(ManageViewSet):
    serializer_class = ManageEventSerializer
    queryset = Event.objects.all()
    filterset_fields = ['community', 'category']

    def get_queryset(self):
        return events_queryset(self.request.user).filter(pk__in=super().get_queryset().values('pk'))

    def perform_create(self, serializer):
        self.assert_can_manage(serializer.validated_data.get('community'))
        event = serializer.save(created_by=self.request.user)
        notify_community_residents(event.community, 'New event', event.title, CAT.COMMUNITY, {'event_id': event.id},
                                   pref='polls_events')

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        self.perform_create(s)
        return Response(self.get_serializer(self.get_queryset().get(pk=s.instance.pk)).data, status=201)


class ManageVendorViewSet(ManageViewSet):
    serializer_class = ManageVendorSerializer
    queryset = ServiceVendor.objects.all()
    filterset_fields = ['community', 'category', 'is_active']
    search_fields = ['name']

    def get_queryset(self):
        return vendors_queryset().filter(pk__in=super().get_queryset().values('pk'))

    def perform_create(self, serializer):
        community = serializer.validated_data.get('community')
        self.assert_can_manage(community)
        serializer.save(currency=community.currency)


class ManageBookingViewSet(mixins.UpdateModelMixin, ManageReadOnlyViewSet):
    queryset = ServiceBooking.objects.select_related('vendor', 'unit__tower')
    community_lookup = 'vendor__community'
    filterset_fields = ['status', 'vendor']
    http_method_names = ['get', 'patch']

    def get_serializer_class(self):
        return BookingStatusSerializer if self.action in ('update', 'partial_update') else BookingSerializer

    def community_from(self, data, instance=None):
        return instance.vendor.community

    def perform_update(self, serializer):
        super().perform_update(serializer)
        b = serializer.instance
        notify_unit(b.unit, f'Booking {b.status}', f'{b.vendor.name} · {b.slot_start:%d %b %H:%M}', CAT.COMMUNITY,
                    {'booking_id': b.id})


class ManageMoveRequestViewSet(ManageReadOnlyViewSet):
    tower_lookup = 'unit__tower'
    serializer_class = MoveRequestSerializer
    queryset = MoveRequest.objects.select_related('unit__tower', 'user').prefetch_related('documents')
    community_lookup = 'unit__tower__community'
    filterset_fields = ['status', 'move_type']

    def _review(self, status_, title):
        m = self.get_object()
        if m.status != MoveRequest.Status.PENDING and status_ != MoveRequest.Status.COMPLETED:
            raise ValidationError({'detail': 'Request has already been reviewed.'})
        s = ReviewNoteSerializer(data=self.request.data)
        s.is_valid(raise_exception=True)
        m.status, m.reviewed_by = status_, self.request.user
        m.review_note = s.validated_data.get('note', '')
        m.save()
        notify([m.user], title, f'{m.get_move_type_display()} on {m.move_date}', CAT.COMMUNITY,
               {'move_request_id': m.id})
        return Response(MoveRequestSerializer(m).data)

    @extend_schema(request=ReviewNoteSerializer, responses=MoveRequestSerializer)
    @action(detail=True, methods=['post'])
    def approve(self, request, pk=None):
        return self._review(MoveRequest.Status.APPROVED, 'Move request approved')

    @extend_schema(request=ReviewNoteSerializer, responses=MoveRequestSerializer)
    @action(detail=True, methods=['post'])
    def reject(self, request, pk=None):
        return self._review(MoveRequest.Status.REJECTED, 'Move request declined')

    @extend_schema(request=ReviewNoteSerializer, responses=MoveRequestSerializer)
    @action(detail=True, methods=['post'])
    def complete(self, request, pk=None):
        return self._review(MoveRequest.Status.COMPLETED, 'Move marked as completed')


class ManageForumViewSet(mixins.DestroyModelMixin, ManageReadOnlyViewSet):
    """Moderation: list, lock/unlock, delete posts."""

    serializer_class = ForumPostSerializer
    queryset = ForumPost.objects.select_related('author', 'unit__tower').annotate(
        likes_count=Count('likes', distinct=True), replies_count=Count('replies', distinct=True))
    filterset_fields = ['community', 'tag', 'is_locked']
    search_fields = ['title', 'body']

    @extend_schema(request=None, responses=ForumPostSerializer)
    @action(detail=True, methods=['post'])
    def lock(self, request, pk=None):
        post = self.get_object()
        post.is_locked = not post.is_locked
        post.save(update_fields=['is_locked'])
        return Response(ForumPostSerializer(self.get_queryset().get(pk=post.pk)).data, status=status.HTTP_200_OK)


class ManageClassifiedViewSet(ManageReadOnlyViewSet):
    serializer_class = ClassifiedSerializer
    queryset = Classified.objects.select_related('seller', 'unit__tower')
    filterset_fields = ['community', 'status', 'category']

    @extend_schema(request=None, responses=ClassifiedSerializer)
    @action(detail=True, methods=['post'])
    def remove(self, request, pk=None):
        item = self.get_object()
        item.status = Classified.Status.REMOVED
        item.save(update_fields=['status'])
        return Response(ClassifiedSerializer(item).data)
