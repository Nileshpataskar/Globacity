from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import mixins, serializers, viewsets
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Device, Notification


class NotificationSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notification
        fields = ['id', 'title', 'body', 'category', 'data', 'is_read', 'read_at', 'created_at']
        read_only_fields = fields


class UnreadCountSerializer(serializers.Serializer):
    unread = serializers.IntegerField()


class DeviceSerializer(serializers.ModelSerializer):
    class Meta:
        model = Device
        fields = ['id', 'token', 'platform', 'created_at']
        read_only_fields = ['id', 'created_at']
        extra_kwargs = {'token': {'validators': []}}


class NotificationViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    serializer_class = NotificationSerializer
    filterset_fields = ['category', 'is_read']

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Notification.objects.none()
        return Notification.objects.filter(user=self.request.user)

    @extend_schema(request=None, responses=NotificationSerializer)
    @action(detail=True, methods=['post'])
    def read(self, request, pk=None):
        n = self.get_object()
        if not n.is_read:
            n.is_read, n.read_at = True, timezone.now()
            n.save(update_fields=['is_read', 'read_at'])
        return Response(NotificationSerializer(n).data)

    @extend_schema(request=None, responses=UnreadCountSerializer)
    @action(detail=False, methods=['post'], url_path='read-all')
    def read_all(self, request):
        self.get_queryset().filter(is_read=False).update(is_read=True, read_at=timezone.now())
        return Response({'unread': 0})

    @extend_schema(responses=UnreadCountSerializer)
    @action(detail=False, methods=['get'], url_path='unread-count')
    def unread_count(self, request):
        return Response({'unread': self.get_queryset().filter(is_read=False).count()})


class DeviceViewSet(mixins.CreateModelMixin, mixins.DestroyModelMixin, viewsets.GenericViewSet):
    """Register a push token after login; delete it on logout."""

    serializer_class = DeviceSerializer

    def get_queryset(self):
        if getattr(self, 'swagger_fake_view', False):
            return Device.objects.none()
        return Device.objects.filter(user=self.request.user)

    def create(self, request, *args, **kwargs):
        s = self.get_serializer(data=request.data)
        s.is_valid(raise_exception=True)
        device, _ = Device.objects.update_or_create(
            token=s.validated_data['token'],
            defaults={'user': request.user, 'platform': s.validated_data['platform']},
        )
        return Response(DeviceSerializer(device).data, status=201)
