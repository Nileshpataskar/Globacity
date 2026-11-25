from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers

from .models import (
    Classified,
    Event,
    ForumPost,
    ForumReply,
    MoveDocument,
    MoveRequest,
    Notice,
    Poll,
    PollVote,
    ServiceBooking,
    ServiceVendor,
)

# ---------------------------------------------------------------------------
# Notices
# ---------------------------------------------------------------------------


class NoticeSerializer(serializers.ModelSerializer):
    class Meta:
        model = Notice
        fields = ['id', 'title', 'body', 'category', 'is_pinned', 'attachment', 'author_label', 'published_at',
                  'expires_at']


class ManageNoticeSerializer(serializers.ModelSerializer):
    notify = serializers.BooleanField(write_only=True, default=True, help_text='Push to residents')

    class Meta:
        model = Notice
        fields = ['id', 'community', 'title', 'body', 'category', 'is_pinned', 'attachment', 'target_towers',
                  'author_label', 'published_at', 'expires_at', 'notify', 'created_at']
        extra_kwargs = {'published_at': {'required': False}}

    def validate(self, attrs):
        community = attrs.get('community') or getattr(self.instance, 'community', None)
        towers = attrs.get('target_towers') or []
        if any(t.community_id != getattr(community, 'pk', None) for t in towers):
            raise serializers.ValidationError({'target_towers': 'Towers must belong to the community.'})
        return attrs


# ---------------------------------------------------------------------------
# Polls
# ---------------------------------------------------------------------------


class PollOptionResultSerializer(serializers.Serializer):
    id = serializers.IntegerField()
    label = serializers.CharField()
    votes = serializers.IntegerField()
    percent = serializers.FloatField()


class PollSerializer(serializers.ModelSerializer):
    is_closed = serializers.SerializerMethodField()
    total_votes = serializers.SerializerMethodField()
    options = serializers.SerializerMethodField()
    my_vote = serializers.SerializerMethodField()

    class Meta:
        model = Poll
        fields = ['id', 'question', 'description', 'closes_at', 'is_closed', 'one_vote_per_unit', 'total_votes',
                  'my_vote', 'options', 'created_at']

    def get_is_closed(self, obj) -> bool:
        return obj.closes_at <= timezone.now()

    def get_total_votes(self, obj) -> int:
        return sum(o.vote_count for o in obj.options.all())

    @extend_schema_field(PollOptionResultSerializer(many=True))
    def get_options(self, obj):
        total = self.get_total_votes(obj) or 1
        return [{'id': o.id, 'label': o.label, 'votes': o.vote_count, 'percent': round(o.vote_count * 100 / total, 1)}
                for o in obj.options.all()]

    def get_my_vote(self, obj) -> int | None:
        request = self.context.get('request')
        if not request or not request.user.is_authenticated:
            return None
        vote = PollVote.objects.filter(poll=obj, user=request.user).values_list('option_id', flat=True).first()
        if vote is None and obj.one_vote_per_unit and 'unit' in self.context:
            vote = PollVote.objects.filter(poll=obj, unit=self.context['unit']).values_list('option_id', flat=True).first()
        return vote


class ManagePollSerializer(PollSerializer):
    option_labels = serializers.ListField(child=serializers.CharField(max_length=150), write_only=True, min_length=2,
                                          required=False, help_text='Options, in order (create only)')

    class Meta(PollSerializer.Meta):
        fields = PollSerializer.Meta.fields + ['community', 'option_labels']

    def validate(self, attrs):
        if self.instance is None and not attrs.get('option_labels'):
            raise serializers.ValidationError({'option_labels': 'Provide at least two options.'})
        return attrs


class VoteSerializer(serializers.Serializer):
    option = serializers.IntegerField()


# ---------------------------------------------------------------------------
# Events
# ---------------------------------------------------------------------------


class EventSerializer(serializers.ModelSerializer):
    attendees = serializers.IntegerField(read_only=True)
    my_guests = serializers.IntegerField(read_only=True, allow_null=True)
    going = serializers.SerializerMethodField()

    class Meta:
        model = Event
        fields = ['id', 'title', 'description', 'category', 'venue', 'starts_at', 'ends_at', 'capacity', 'cover',
                  'attendees', 'going', 'my_guests', 'created_at']

    def get_going(self, obj) -> bool:
        return getattr(obj, 'my_guests', None) is not None


class ManageEventSerializer(EventSerializer):
    class Meta(EventSerializer.Meta):
        fields = EventSerializer.Meta.fields + ['community']


class RSVPSerializer(serializers.Serializer):
    going = serializers.BooleanField()
    guests = serializers.IntegerField(min_value=1, max_value=20, default=1)


# ---------------------------------------------------------------------------
# Forum
# ---------------------------------------------------------------------------


class ForumReplySerializer(serializers.ModelSerializer):
    author_id = serializers.UUIDField(source='author.id', read_only=True)
    author_name = serializers.CharField(source='author.full_name', read_only=True)

    class Meta:
        model = ForumReply
        fields = ['id', 'body', 'author_id', 'author_name', 'created_at']


class ForumPostSerializer(serializers.ModelSerializer):
    author_id = serializers.UUIDField(source='author.id', read_only=True)
    author_name = serializers.CharField(source='author.full_name', read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    likes_count = serializers.IntegerField(read_only=True)
    replies_count = serializers.IntegerField(read_only=True)
    liked = serializers.BooleanField(read_only=True)

    class Meta:
        model = ForumPost
        fields = ['id', 'title', 'body', 'tag', 'is_locked', 'author_id', 'author_name', 'unit_label', 'likes_count',
                  'replies_count', 'liked', 'created_at']
        read_only_fields = ['is_locked']


# ---------------------------------------------------------------------------
# Classifieds & marketplace
# ---------------------------------------------------------------------------


class ClassifiedSerializer(serializers.ModelSerializer):
    seller_id = serializers.UUIDField(source='seller.id', read_only=True)
    seller_name = serializers.CharField(source='seller.full_name', read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)

    class Meta:
        model = Classified
        fields = ['id', 'title', 'description', 'category', 'price', 'currency', 'image', 'status', 'seller_id',
                  'seller_name', 'unit_label', 'created_at']
        read_only_fields = ['currency', 'status']


class VendorSerializer(serializers.ModelSerializer):
    rating = serializers.FloatField(read_only=True)

    class Meta:
        model = ServiceVendor
        fields = ['id', 'name', 'category', 'description', 'phone', 'price_from', 'currency', 'eta_text', 'logo',
                  'rating']
        read_only_fields = ['currency']


class ManageVendorSerializer(VendorSerializer):
    class Meta(VendorSerializer.Meta):
        fields = VendorSerializer.Meta.fields + ['community', 'is_active']


class BookingSerializer(serializers.ModelSerializer):
    vendor_name = serializers.CharField(source='vendor.name', read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)

    class Meta:
        model = ServiceBooking
        fields = ['id', 'vendor', 'vendor_name', 'unit_label', 'slot_start', 'notes', 'status', 'rating',
                  'created_at']
        read_only_fields = ['status', 'rating']


class BookingStatusSerializer(serializers.ModelSerializer):
    class Meta:
        model = ServiceBooking
        fields = ['status']


class RatingSerializer(serializers.Serializer):
    rating = serializers.IntegerField(min_value=1, max_value=5)


# ---------------------------------------------------------------------------
# Move in / out
# ---------------------------------------------------------------------------


class MoveDocumentSerializer(serializers.ModelSerializer):
    class Meta:
        model = MoveDocument
        fields = ['id', 'doc_type', 'file', 'created_at']


class MoveRequestSerializer(serializers.ModelSerializer):
    documents = MoveDocumentSerializer(many=True, read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    requested_by = serializers.CharField(source='user.full_name', read_only=True)

    class Meta:
        model = MoveRequest
        fields = ['id', 'move_type', 'move_date', 'moving_company', 'service_lift', 'notes', 'status', 'review_note',
                  'unit', 'unit_label', 'requested_by', 'documents', 'created_at']
        read_only_fields = ['status', 'review_note', 'unit']

    def validate_move_date(self, value):
        if self.instance is None and value < timezone.localdate():
            raise serializers.ValidationError('Must be today or later.')
        return value


class ReviewNoteSerializer(serializers.Serializer):
    note = serializers.CharField(required=False, allow_blank=True)
