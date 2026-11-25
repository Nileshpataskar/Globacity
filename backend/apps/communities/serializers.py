from django.utils.text import slugify
from rest_framework import serializers

from apps.accounts.serializers import UserMiniSerializer

from .models import Community, EmergencyContact, Gate, Membership, StaffMember, Tower, Unit


def unique_slug(name, model=Community):
    base = slugify(name)[:150] or 'community'
    slug, i = base, 2
    while model.objects.filter(slug=slug).exists():
        slug, i = f'{base}-{i}', i + 1
    return slug


class CommunitySerializer(serializers.ModelSerializer):
    city_name = serializers.CharField(source='city.name', read_only=True)
    country = serializers.CharField(source='city.country.iso2', read_only=True)
    currency = serializers.CharField(source='city.country.currency_id', read_only=True)
    slug = serializers.SlugField(required=False)

    class Meta:
        model = Community
        fields = [
            'id', 'city', 'city_name', 'country', 'currency', 'name', 'slug', 'address', 'latitude', 'longitude',
            'contact_phone', 'contact_email', 'timezone', 'logo', 'primary_color', 'secondary_color', 'settings',
            'is_active', 'created_at',
        ]

    def create(self, validated_data):
        validated_data.setdefault('slug', unique_slug(validated_data['name']))
        return super().create(validated_data)


class ManagedCommunitySerializer(CommunitySerializer):
    """Community admins can edit branding and settings, not the city or slug."""

    class Meta(CommunitySerializer.Meta):
        read_only_fields = ['city', 'slug', 'is_active']


class CommunityPublicSerializer(serializers.ModelSerializer):
    city = serializers.CharField(source='city.name')
    country = serializers.CharField(source='city.country.name')

    class Meta:
        model = Community
        fields = ['id', 'name', 'address', 'city', 'country', 'logo']


class TowerSerializer(serializers.ModelSerializer):
    units_count = serializers.IntegerField(read_only=True)

    class Meta:
        model = Tower
        fields = ['id', 'community', 'name', 'code', 'floors', 'units_count', 'approval_mode', 'maintenance_amount',
                  'lifts', 'parking_slots', 'contact_name', 'contact_phone', 'created_at']


class TowerPublicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Tower
        fields = ['id', 'name', 'floors']


class GenerateUnitsSerializer(serializers.Serializer):
    floor_from = serializers.IntegerField(min_value=0)
    floor_to = serializers.IntegerField(min_value=0)
    units_per_floor = serializers.IntegerField(min_value=1, max_value=100)
    unit_type = serializers.ChoiceField(choices=Unit.Type.choices, default=Unit.Type.APARTMENT)
    number_format = serializers.CharField(
        default='{floor}{index:02d}', help_text='Python format with {floor} and {index}, e.g. "{floor}{index:02d}" -> 1204'
    )

    def validate(self, attrs):
        if attrs['floor_to'] < attrs['floor_from']:
            raise serializers.ValidationError({'floor_to': 'Must be >= floor_from.'})
        try:
            attrs['number_format'].format(floor=1, index=1)
        except (KeyError, ValueError, IndexError):
            raise serializers.ValidationError({'number_format': 'Invalid format.'})
        return attrs


class GenerateUnitsResponseSerializer(serializers.Serializer):
    created = serializers.IntegerField()
    skipped = serializers.IntegerField()


class UnitSerializer(serializers.ModelSerializer):
    tower_name = serializers.CharField(source='tower.name', read_only=True)
    community = serializers.UUIDField(source='tower.community_id', read_only=True)

    class Meta:
        model = Unit
        fields = ['id', 'tower', 'tower_name', 'community', 'number', 'floor', 'unit_type', 'bedrooms', 'area_sqft',
                  'label', 'created_at']


class UnitPublicSerializer(serializers.ModelSerializer):
    class Meta:
        model = Unit
        fields = ['id', 'number', 'floor', 'unit_type', 'tower']


class GateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Gate
        fields = ['id', 'community', 'name', 'is_active', 'iot_enabled', 'iot_device_id', 'created_at']


class UnitSummarySerializer(serializers.ModelSerializer):
    tower = serializers.CharField(source='tower.name')
    community = serializers.SerializerMethodField()

    class Meta:
        model = Unit
        fields = ['id', 'number', 'tower', 'label', 'community']

    def get_community(self, obj) -> dict:
        c = obj.tower.community
        country = c.city.country
        return {
            'id': str(c.id), 'name': c.name, 'city': c.city.name, 'country': country.name,
            'currency': country.currency_id,
        }


class MembershipSerializer(serializers.ModelSerializer):
    """The caller's own unit memberships ("My properties")."""

    unit_detail = UnitSummarySerializer(source='unit', read_only=True)

    class Meta:
        model = Membership
        fields = ['id', 'unit', 'unit_detail', 'role', 'status', 'note', 'approved_at', 'created_at']
        read_only_fields = ['status', 'approved_at']

    def validate_unit(self, unit):
        user = self.context['request'].user
        if Membership.objects.filter(user=user, unit=unit).exclude(status=Membership.Status.REJECTED).exists():
            raise serializers.ValidationError('You already have a request or membership for this unit.')
        return unit


class ManageMembershipSerializer(serializers.ModelSerializer):
    user = UserMiniSerializer(read_only=True)
    unit_label = serializers.CharField(source='unit.label', read_only=True)
    user_phone = serializers.CharField(write_only=True, required=False, help_text='Add a resident directly by phone')
    full_name = serializers.CharField(write_only=True, required=False, allow_blank=True)

    class Meta:
        model = Membership
        fields = ['id', 'user', 'unit', 'unit_label', 'role', 'status', 'note', 'approved_at', 'created_at',
                  'user_phone', 'full_name']
        read_only_fields = ['status', 'approved_at']


class StaffMemberSerializer(serializers.ModelSerializer):
    user_phone = serializers.CharField(
        write_only=True, required=False, help_text='Give this person an app login (admins, managers, guards)'
    )

    class Meta:
        model = StaffMember
        fields = ['id', 'community', 'user', 'user_phone', 'name', 'phone', 'role', 'designation', 'shift',
                  'show_in_directory', 'is_active', 'towers', 'tower_names', 'created_at']
        read_only_fields = ['user']

    tower_names = serializers.SerializerMethodField()

    def get_tower_names(self, obj):
        return [t.name for t in obj.towers.all()]

    def validate(self, attrs):
        community = attrs.get('community') or getattr(self.instance, 'community', None)
        if any(t.community_id != getattr(community, 'pk', None) for t in attrs.get('towers', [])):
            raise serializers.ValidationError({'towers': 'Towers must belong to the same community.'})
        return attrs


class EmergencyContactSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmergencyContact
        fields = ['id', 'community', 'name', 'phone', 'group', 'icon', 'order']
        read_only_fields = ['group']


class PersonalContactSerializer(serializers.ModelSerializer):
    class Meta:
        model = EmergencyContact
        fields = ['id', 'name', 'phone', 'icon']


class ContactItemSerializer(serializers.Serializer):
    id = serializers.CharField(allow_null=True)
    name = serializers.CharField()
    phone = serializers.CharField()
    group = serializers.ChoiceField(choices=['public', 'community', 'personal'])
    icon = serializers.CharField(allow_blank=True)


class DirectoryResidentSerializer(serializers.Serializer):
    user_id = serializers.UUIDField()
    name = serializers.CharField()
    unit = serializers.CharField(allow_null=True)
    phone = serializers.CharField(allow_null=True)
    role = serializers.CharField()
    can_message = serializers.BooleanField()


class DirectoryStaffSerializer(serializers.ModelSerializer):
    role_label = serializers.CharField(source='get_role_display')

    class Meta:
        model = StaffMember
        fields = ['id', 'user', 'name', 'phone', 'role', 'role_label', 'designation', 'shift']
