from django.contrib import admin

from .models import Community, EmergencyContact, Gate, Membership, StaffMember, Tower, Unit


class TowerInline(admin.TabularInline):
    model = Tower
    extra = 0


class GateInline(admin.TabularInline):
    model = Gate
    extra = 0


@admin.register(Community)
class CommunityAdmin(admin.ModelAdmin):
    list_display = ['name', 'city', 'is_active', 'created_at']
    list_filter = ['is_active', 'city__country', 'city']
    search_fields = ['name', 'address']
    prepopulated_fields = {'slug': ['name']}
    inlines = [TowerInline, GateInline]


@admin.register(Tower)
class TowerAdmin(admin.ModelAdmin):
    list_display = ['name', 'community', 'floors']
    list_filter = ['community']


@admin.register(Unit)
class UnitAdmin(admin.ModelAdmin):
    list_display = ['number', 'tower', 'floor', 'unit_type']
    list_filter = ['tower__community', 'tower', 'unit_type']
    search_fields = ['number']


@admin.register(Membership)
class MembershipAdmin(admin.ModelAdmin):
    list_display = ['user', 'unit', 'role', 'status', 'created_at']
    list_filter = ['status', 'role', 'unit__tower__community']
    search_fields = ['user__phone', 'user__full_name', 'unit__number']
    raw_id_fields = ['user', 'unit', 'approved_by']
    actions = ['approve_requests', 'reject_requests']

    def _set_status(self, request, queryset, status, title):
        from django.utils import timezone

        from apps.notifications.models import Notification
        from apps.notifications.service import notify

        for m in queryset.select_related('user', 'unit__tower'):
            m.status, m.approved_by, m.approved_at = status, request.user, timezone.now()
            m.save(update_fields=['status', 'approved_by', 'approved_at'])
            notify([m.user], title, m.unit.label, Notification.Category.COMMUNITY, {'membership_id': m.id})
        self.message_user(request, f'{queryset.count()} request(s) updated.')

    @admin.action(description='Approve selected unit requests')
    def approve_requests(self, request, queryset):
        self._set_status(request, queryset, Membership.Status.APPROVED, 'Your unit request was approved')

    @admin.action(description='Reject selected unit requests')
    def reject_requests(self, request, queryset):
        self._set_status(request, queryset, Membership.Status.REJECTED, 'Your unit request was declined')


@admin.register(StaffMember)
class StaffMemberAdmin(admin.ModelAdmin):
    list_display = ['name', 'community', 'role', 'designation', 'user', 'is_active']
    list_filter = ['role', 'community', 'is_active']
    search_fields = ['name', 'phone']
    raw_id_fields = ['user']


admin.site.register(Gate)
admin.site.register(EmergencyContact)
