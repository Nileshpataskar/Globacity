from django.db.models import Count, F, OuterRef, Q, Subquery
from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, serializers, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import PermissionDenied, ValidationError
from rest_framework.response import Response

from apps.accounts.models import User, UserSettings
from apps.communities.models import Membership, StaffMember
from apps.core.scoping import UnitScopedMixin
from apps.notifications.models import Notification
from apps.notifications.service import notify

from .models import Conversation, Message, Participant


class MessageSerializer(serializers.ModelSerializer):
    sender_id = serializers.UUIDField(source='sender.id', read_only=True)
    sender_name = serializers.CharField(source='sender.full_name', read_only=True)
    is_mine = serializers.SerializerMethodField()

    class Meta:
        model = Message
        fields = ['id', 'body', 'sender_id', 'sender_name', 'is_mine', 'created_at']

    def get_is_mine(self, obj) -> bool:
        return obj.sender_id == self.context['request'].user.pk


class ConversationSerializer(serializers.ModelSerializer):
    other_user = serializers.SerializerMethodField()
    last_message = serializers.CharField(read_only=True, allow_null=True)
    unread = serializers.IntegerField(read_only=True)

    class Meta:
        model = Conversation
        fields = ['id', 'other_user', 'last_message', 'last_message_at', 'unread', 'created_at']

    def get_other_user(self, obj) -> dict:
        me = self.context['request'].user
        other = next((u for u in obj.participants.all() if u.pk != me.pk), me)
        return {'id': str(other.pk), 'name': other.full_name or other.phone}


class StartConversationSerializer(serializers.Serializer):
    user_id = serializers.UUIDField()


def _in_community(user, community):
    return (Membership.objects.filter(user=user, unit__tower__community=community,
                                      status=Membership.Status.APPROVED).exists()
            or StaffMember.objects.filter(user=user, community=community, is_active=True).exists())


class ConversationViewSet(UnitScopedMixin, mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """One-to-one chats inside your current community."""

    serializer_class = ConversationSerializer

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Conversation.objects.none()
        user = self.request.user
        last = Message.objects.filter(conversation=OuterRef('pk')).order_by('-created_at')
        my_read = Participant.objects.filter(conversation=OuterRef('pk'), user=user).values('last_read_at')[:1]
        return (Conversation.objects.filter(community=self.community, memberships__user=user)
                .prefetch_related('participants')
                .annotate(last_message=Subquery(last.values('body')[:1]), my_last_read=Subquery(my_read))
                .annotate(unread=Count('messages', filter=~Q(messages__sender=user) & (
                    Q(my_last_read__isnull=True) | Q(messages__created_at__gt=F('my_last_read'))), distinct=True)))

    @extend_schema(request=StartConversationSerializer, responses=ConversationSerializer)
    def create(self, request):
        """Open (or reuse) a chat with a resident or staff member of this community."""
        s = StartConversationSerializer(data=request.data)
        s.is_valid(raise_exception=True)
        other = User.objects.filter(pk=s.validated_data['user_id'], is_active=True).first()
        if other is None or other.pk == request.user.pk or not _in_community(other, self.community):
            raise ValidationError({'user_id': 'You can only message people in your community.'})
        if not UserSettings.for_user(other).privacy_prefs.get('allow_messages', True):
            raise PermissionDenied('This person does not accept messages.')
        existing = (Conversation.objects.filter(community=self.community, memberships__user=request.user)
                    .filter(memberships__user=other).first())
        conv = existing or Conversation.objects.create(community=self.community)
        if not existing:
            Participant.objects.bulk_create([Participant(conversation=conv, user=request.user),
                                             Participant(conversation=conv, user=other)])
        return Response(self.get_serializer(self.get_queryset().get(pk=conv.pk)).data, status=201 if not existing else 200)

    @extend_schema(methods=['get'], responses=MessageSerializer(many=True))
    @extend_schema(methods=['post'], request=MessageSerializer, responses=MessageSerializer)
    @action(detail=True, methods=['get', 'post'])
    def messages(self, request, pk=None):
        conv = self.get_object()
        if request.method == 'GET':
            page = self.paginate_queryset(conv.messages.select_related('sender').order_by('-created_at'))
            Participant.objects.filter(conversation=conv, user=request.user).update(last_read_at=timezone.now())
            return self.get_paginated_response(MessageSerializer(page, many=True, context={'request': request}).data)
        s = MessageSerializer(data=request.data, context={'request': request})
        s.is_valid(raise_exception=True)
        msg = s.save(conversation=conv, sender=request.user)
        conv.last_message_at = msg.created_at
        conv.save(update_fields=['last_message_at'])
        Participant.objects.filter(conversation=conv, user=request.user).update(last_read_at=msg.created_at)
        others = [u for u in conv.participants.all() if u.pk != request.user.pk]
        notify(others, request.user.full_name or 'New message', msg.body[:120], Notification.Category.MESSAGE,
               {'conversation_id': conv.id})
        return Response(MessageSerializer(msg, context={'request': request}).data, status=201)
