from rest_framework import serializers

from .models import DailyHelp, DailyHelpAttendance, DailyHelpReview, FamilyMember, Pet, Vehicle


class FamilyMemberSerializer(serializers.ModelSerializer):
    class Meta:
        model = FamilyMember
        fields = ['id', 'name', 'relation', 'phone', 'date_of_birth', 'is_minor', 'created_at']


class VehicleSerializer(serializers.ModelSerializer):
    class Meta:
        model = Vehicle
        fields = ['id', 'number', 'make_model', 'color', 'vehicle_type', 'parking_slot', 'created_at']


class PetSerializer(serializers.ModelSerializer):
    class Meta:
        model = Pet
        fields = ['id', 'name', 'species', 'breed', 'vaccinated', 'created_at']


class DailyHelpSerializer(serializers.ModelSerializer):
    timing = serializers.CharField(required=False, allow_blank=True, write_only=True)
    my_timing = serializers.SerializerMethodField()
    rating = serializers.FloatField(read_only=True)
    reviews_count = serializers.IntegerField(read_only=True)
    homes_served = serializers.IntegerField(read_only=True)
    is_inside = serializers.BooleanField(read_only=True)
    last_entry = serializers.DateTimeField(read_only=True)

    class Meta:
        model = DailyHelp
        fields = ['id', 'name', 'phone', 'role', 'photo', 'id_verified', 'pass_code', 'timing', 'my_timing',
                  'rating', 'reviews_count', 'homes_served', 'is_inside', 'last_entry', 'created_at']
        read_only_fields = ['id_verified', 'pass_code']
        extra_kwargs = {'phone': {'validators': []}}

    def get_my_timing(self, obj) -> str:
        unit = self.context.get('unit')
        for a in getattr(obj, 'my_assignments', []):
            if a.unit_id == getattr(unit, 'pk', None):
                return a.timing
        return ''


class DailyHelpReviewSerializer(serializers.ModelSerializer):
    author_name = serializers.CharField(source='author.full_name', read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)

    class Meta:
        model = DailyHelpReview
        fields = ['id', 'rating', 'comment', 'author_name', 'unit_label', 'created_at']


class AttendanceRecordSerializer(serializers.ModelSerializer):
    class Meta:
        model = DailyHelpAttendance
        fields = ['date', 'check_in', 'check_out']


class AttendanceMonthSerializer(serializers.Serializer):
    month = serializers.CharField()
    present_days = serializers.ListField(child=serializers.IntegerField())
    days_present = serializers.IntegerField()
    records = AttendanceRecordSerializer(many=True)
