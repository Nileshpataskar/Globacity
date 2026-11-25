from rest_framework import serializers

from .models import Ticket, TicketAttachment, TicketCategory, TicketUpdate


class TicketCategorySerializer(serializers.ModelSerializer):
    class Meta:
        model = TicketCategory
        fields = ['id', 'community', 'name', 'icon', 'sla_hours', 'is_active']


class TicketUpdateSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source='author.full_name', read_only=True, default='System')

    class Meta:
        model = TicketUpdate
        fields = ['id', 'message', 'status_change', 'author_name', 'is_internal', 'created_at']
        read_only_fields = ['status_change', 'is_internal']


class StaffCommentSerializer(TicketUpdateSerializer):
    class Meta(TicketUpdateSerializer.Meta):
        read_only_fields = ['status_change']


class TicketAttachmentSerializer(serializers.ModelSerializer):
    class Meta:
        model = TicketAttachment
        fields = ['id', 'file', 'created_at']


class TicketSerializer(serializers.ModelSerializer):
    category_name = serializers.CharField(source='category.name', read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    raised_by_name = serializers.CharField(source='raised_by.full_name', read_only=True)
    assigned_to_name = serializers.CharField(source='assigned_to.name', read_only=True, default=None)
    updates = serializers.SerializerMethodField()
    attachments = TicketAttachmentSerializer(many=True, read_only=True)

    class Meta:
        model = Ticket
        fields = ['id', 'number', 'title', 'description', 'category', 'category_name', 'priority', 'status',
                  'unit_label', 'raised_by_name', 'assigned_to', 'assigned_to_name', 'resolved_at', 'rating',
                  'rating_comment', 'attachments', 'updates', 'created_at']
        read_only_fields = ['number', 'status', 'assigned_to', 'resolved_at', 'rating', 'rating_comment']

    def get_updates(self, obj) -> list[dict]:
        staff_view = self.context.get('staff_view', False)
        updates = [u for u in obj.updates.all() if staff_view or not u.is_internal]
        return TicketUpdateSerializer(updates, many=True).data


class ManageTicketSerializer(TicketSerializer):
    class Meta(TicketSerializer.Meta):
        read_only_fields = ['number', 'title', 'description', 'category', 'resolved_at', 'rating', 'rating_comment']


class TicketRatingSerializer(serializers.Serializer):
    rating = serializers.IntegerField(min_value=1, max_value=5)
    comment = serializers.CharField(required=False, allow_blank=True, max_length=255)
