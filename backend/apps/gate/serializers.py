from datetime import timedelta

from django.utils import timezone
from rest_framework import serializers

from apps.household.models import FamilyMember

from .models import FrequentEntry, KidExitPermission, SOSAlert, Visitor


class VisitorSerializer(serializers.ModelSerializer):
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    gate_name = serializers.CharField(source='gate.name', read_only=True, default=None)
    status_label = serializers.CharField(source='get_status_display', read_only=True)

    class Meta:
        model = Visitor
        fields = [
            'id', 'name', 'phone', 'visitor_type', 'company', 'vehicle_no', 'guests', 'note', 'photo', 'status',
            'status_label', 'pass_code', 'expected_at', 'valid_until', 'is_walk_in', 'gate', 'gate_name',
            'unit', 'unit_label', 'responded_at', 'checked_in_at', 'checked_out_at', 'created_at',
        ]
        read_only_fields = ['status', 'pass_code', 'is_walk_in', 'gate', 'unit', 'responded_at', 'checked_in_at',
                            'checked_out_at']


class PreApproveSerializer(VisitorSerializer):
    """Resident pre-approval. ``expected_at`` defaults to now; the pass is valid for ``valid_hours``."""

    valid_hours = serializers.IntegerField(write_only=True, required=False, min_value=1, max_value=72, default=12)

    class Meta(VisitorSerializer.Meta):
        fields = VisitorSerializer.Meta.fields + ['valid_hours']
        read_only_fields = VisitorSerializer.Meta.read_only_fields + ['valid_until']

    def validate(self, attrs):
        attrs['expected_at'] = attrs.get('expected_at') or timezone.now()
        attrs['valid_until'] = attrs['expected_at'] + timedelta(hours=attrs.pop('valid_hours', 12))
        if attrs['valid_until'] < timezone.now():
            raise serializers.ValidationError({'expected_at': 'Must be in the future.'})
        return attrs


class WalkInSerializer(serializers.ModelSerializer):
    class Meta:
        model = Visitor
        fields = ['unit', 'name', 'phone', 'visitor_type', 'company', 'vehicle_no', 'guests', 'note', 'photo', 'gate']


class FrequentEntrySerializer(serializers.ModelSerializer):
    class Meta:
        model = FrequentEntry
        fields = ['id', 'name', 'phone', 'visitor_type', 'company', 'valid_from', 'valid_until', 'days_of_week',
                  'time_from', 'time_to', 'pass_code', 'is_active', 'created_at']
        read_only_fields = ['pass_code']

    def validate_days_of_week(self, value):
        if not isinstance(value, list) or any(not isinstance(d, int) or d < 0 or d > 6 for d in value):
            raise serializers.ValidationError('List of integers 0 (Mon) to 6 (Sun).')
        return sorted(set(value))

    def validate(self, attrs):
        start = attrs.get('valid_from', getattr(self.instance, 'valid_from', None))
        end = attrs.get('valid_until', getattr(self.instance, 'valid_until', None))
        if start and end and end < start:
            raise serializers.ValidationError({'valid_until': 'Must be on or after valid_from.'})
        return attrs


class ChildSerializer(serializers.ModelSerializer):
    class Meta:
        model = FamilyMember
        fields = ['id', 'name']


class KidExitSerializer(serializers.ModelSerializer):
    children = serializers.PrimaryKeyRelatedField(many=True, queryset=FamilyMember.objects.filter(is_minor=True))
    children_detail = ChildSerializer(source='children', many=True, read_only=True)
    duration_minutes = serializers.IntegerField(write_only=True, required=False, min_value=10, max_value=24 * 60)
    unit_label = serializers.CharField(source='unit.label', read_only=True)

    class Meta:
        model = KidExitPermission
        fields = ['id', 'children', 'children_detail', 'allowed_from', 'allowed_until', 'duration_minutes', 'note',
                  'status', 'unit_label', 'created_at']
        read_only_fields = ['status']
        extra_kwargs = {'allowed_from': {'required': False}, 'allowed_until': {'required': False}}

    def validate_children(self, children):
        unit = self.context['view'].unit
        if not children:
            raise serializers.ValidationError('Select at least one child.')
        if any(c.unit_id != unit.pk for c in children):
            raise serializers.ValidationError('Children must belong to your unit.')
        return children

    def validate(self, attrs):
        start = attrs.get('allowed_from') or timezone.now()
        minutes = attrs.pop('duration_minutes', None)
        end = attrs.get('allowed_until') or (start + timedelta(minutes=minutes or 60))
        if end <= start:
            raise serializers.ValidationError({'allowed_until': 'Must be after allowed_from.'})
        attrs['allowed_from'], attrs['allowed_until'] = start, end
        return attrs


class SOSAlertSerializer(serializers.ModelSerializer):
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    raised_by_name = serializers.CharField(source='raised_by.full_name', read_only=True)
    raised_by_phone = serializers.CharField(source='raised_by.phone', read_only=True)

    class Meta:
        model = SOSAlert
        fields = ['id', 'alert_type', 'message', 'status', 'unit', 'unit_label', 'raised_by_name', 'raised_by_phone',
                  'acknowledged_at', 'resolved_at', 'created_at']
        read_only_fields = ['status', 'unit', 'acknowledged_at', 'resolved_at']


class CodeSerializer(serializers.Serializer):
    code = serializers.CharField(min_length=6, max_length=6)
    gate = serializers.UUIDField(required=False)


class CodeLookupSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=['visitor', 'frequent_entry', 'daily_help'])
    id = serializers.UUIDField()
    name = serializers.CharField()
    detail = serializers.CharField(help_text='Type / role / company')
    units = serializers.ListField(child=serializers.CharField())
    allowed = serializers.BooleanField()
    reason = serializers.CharField(allow_blank=True)
