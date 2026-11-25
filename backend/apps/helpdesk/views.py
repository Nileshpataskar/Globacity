from django.db import IntegrityError, transaction
from django.db.models import Q
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import MethodNotAllowed, ValidationError
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response

from apps.core.permissions import MANAGER_ROLES
from apps.core.scoping import ManageViewSet, UnitScopedCreateListViewSet, UnitScopedMixin
from apps.notifications.models import Notification
from apps.notifications.service import notify_community_staff, notify_unit

from .models import Ticket, TicketCategory, TicketUpdate
from .serializers import (
    ManageTicketSerializer,
    StaffCommentSerializer,
    TicketAttachmentSerializer,
    TicketCategorySerializer,
    TicketRatingSerializer,
    TicketSerializer,
    TicketUpdateSerializer,
)

CAT = Notification.Category
OPEN_STATUSES = [Ticket.Status.OPEN, Ticket.Status.IN_PROGRESS, Ticket.Status.ON_HOLD]


def categories_for(community):
    return TicketCategory.objects.filter(Q(community=community) | Q(community__isnull=True), is_active=True)


def next_ticket_number(community, attempt=0):
    return f'T-{1001 + Ticket.objects.filter(community=community).count() + attempt}'


class TicketCategoryViewSet(UnitScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = TicketCategorySerializer
    pagination_class = None

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return TicketCategory.objects.none()
        return categories_for(self.community)


class TicketViewSet(UnitScopedCreateListViewSet):
    """Raise and follow maintenance requests and complaints."""

    serializer_class = TicketSerializer
    queryset = Ticket.objects.select_related('category', 'unit__tower', 'raised_by', 'assigned_to').prefetch_related(
        'updates__author', 'attachments')
    tower_lookup = 'unit__tower'
    filterset_fields = ['status', 'category', 'priority']
    search_fields = ['title', 'number']

    def get_queryset(self):
        qs = super().get_queryset()
        if self.request.query_params.get('active') == 'true':
            qs = qs.filter(status__in=OPEN_STATUSES)
        return qs

    def perform_create(self, serializer):
        category = serializer.validated_data['category']
        if not categories_for(self.community).filter(pk=category.pk).exists():
            raise ValidationError({'category': 'Not available in your community.'})
        for attempt in range(5):
            try:
                with transaction.atomic():
                    t = serializer.save(community=self.community, unit=self.unit, raised_by=self.request.user,
                                        number=next_ticket_number(self.community, attempt))
                break
            except IntegrityError:
                serializer.instance = None
        else:
            raise ValidationError({'detail': 'Please retry.'})
        TicketUpdate.objects.create(ticket=t, author=self.request.user, message='Ticket raised',
                                    status_change=Ticket.Status.OPEN)
        notify_community_staff(self.community, MANAGER_ROLES, f'New ticket {t.number}', f'{t.title} · {t.unit.label}',
                               CAT.HELPDESK, {'ticket_id': t.id})

    @extend_schema(request=TicketUpdateSerializer, responses=TicketUpdateSerializer)
    @action(detail=True, methods=['post'])
    def comment(self, request, pk=None):
        t = self.get_object()
        s = TicketUpdateSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        update = s.save(ticket=t, author=request.user)
        notify_community_staff(t.community, MANAGER_ROLES, f'{t.number}: new comment', update.message[:120],
                               CAT.HELPDESK, {'ticket_id': t.id})
        return Response(TicketUpdateSerializer(update).data, status=201)

    @extend_schema(request={'multipart/form-data': TicketAttachmentSerializer}, responses=TicketAttachmentSerializer)
    @action(detail=True, methods=['post'], parser_classes=[MultiPartParser, FormParser])
    def attachments(self, request, pk=None):
        t = self.get_object()
        s = TicketAttachmentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        s.save(ticket=t, uploaded_by=request.user)
        return Response(s.data, status=201)

    @extend_schema(request=TicketRatingSerializer, responses=TicketSerializer)
    @action(detail=True, methods=['post'])
    def rate(self, request, pk=None):
        t = self.get_object()
        if t.status not in (Ticket.Status.RESOLVED, Ticket.Status.CLOSED):
            raise ValidationError({'detail': 'You can rate resolved tickets only.'})
        s = TicketRatingSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        t.rating, t.rating_comment = s.validated_data['rating'], s.validated_data.get('comment', '')
        t.status = Ticket.Status.CLOSED
        t.save(update_fields=['rating', 'rating_comment', 'status'])
        return Response(TicketSerializer(t).data)

    @extend_schema(request=TicketUpdateSerializer, responses=TicketSerializer)
    @action(detail=True, methods=['post'])
    def reopen(self, request, pk=None):
        t = self.get_object()
        if t.status not in (Ticket.Status.RESOLVED, Ticket.Status.CLOSED):
            raise ValidationError({'detail': 'Ticket is still open.'})
        t.status, t.resolved_at = Ticket.Status.OPEN, None
        t.save(update_fields=['status', 'resolved_at'])
        TicketUpdate.objects.create(ticket=t, author=request.user, status_change=t.status,
                                    message=request.data.get('message') or 'Reopened by resident')
        notify_community_staff(t.community, MANAGER_ROLES, f'{t.number} reopened', t.title, CAT.HELPDESK,
                               {'ticket_id': t.id})
        return Response(TicketSerializer(t).data)


class ManageTicketCategoryViewSet(ManageViewSet):
    readable_by_tower_admins = True
    serializer_class = TicketCategorySerializer
    queryset = TicketCategory.objects.all()
    filterset_fields = ['community', 'is_active']


class ManageTicketViewSet(ManageViewSet):
    """Assign, prioritise and update ticket status. Status changes are logged and pushed to the resident."""

    serializer_class = ManageTicketSerializer
    queryset = Ticket.objects.select_related('category', 'unit__tower', 'raised_by', 'assigned_to').prefetch_related(
        'updates__author', 'attachments')
    filterset_fields = ['community', 'status', 'priority', 'category', 'assigned_to']
    search_fields = ['title', 'number', 'unit__number']
    http_method_names = ['get', 'patch', 'post']

    def create(self, request, *args, **kwargs):
        raise MethodNotAllowed('POST', 'Tickets are raised by residents.')

    def get_serializer_context(self):
        return {**super().get_serializer_context(), 'staff_view': True}

    def perform_update(self, serializer):
        t = serializer.instance
        old_status, old_assignee = t.status, t.assigned_to_id
        assignee = serializer.validated_data.get('assigned_to')
        if assignee and assignee.community_id != t.community_id:
            raise ValidationError({'assigned_to': 'Staff member is from another community.'})
        extra = {}
        new_status = serializer.validated_data.get('status', old_status)
        if new_status == Ticket.Status.RESOLVED and old_status != new_status:
            extra['resolved_at'] = timezone.now()
        super().perform_update(serializer)
        if extra:
            Ticket.objects.filter(pk=t.pk).update(**extra)
        t.refresh_from_db()
        if t.assigned_to_id != old_assignee and t.assigned_to:
            TicketUpdate.objects.create(ticket=t, author=self.request.user,
                                        message=f'Assigned to {t.assigned_to.name}')
        if t.status != old_status:
            TicketUpdate.objects.create(ticket=t, author=self.request.user, status_change=t.status,
                                        message=f'Status changed to {t.get_status_display()}')
            notify_unit(t.unit, f'{t.number}: {t.get_status_display()}', t.title, CAT.HELPDESK, {'ticket_id': t.id},
                        pref='helpdesk_updates')

    @extend_schema(request=StaffCommentSerializer, responses=StaffCommentSerializer)
    @action(detail=True, methods=['post'])
    def comment(self, request, pk=None):
        t = self.get_object()
        s = StaffCommentSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        update = s.save(ticket=t, author=request.user)
        if not update.is_internal:
            notify_unit(t.unit, f'{t.number}: new update', update.message[:120], CAT.HELPDESK, {'ticket_id': t.id},
                        pref='helpdesk_updates')
        return Response(StaffCommentSerializer(update).data, status=201)
