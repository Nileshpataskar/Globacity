from django.contrib import admin

from .models import (
    FrequentEntry,
    GateEvent,
    GuardShift,
    Incident,
    KidExitPermission,
    SOSAlert,
    StaffAttendance,
    VehicleLog,
    Visitor,
)


@admin.register(Visitor)
class VisitorAdmin(admin.ModelAdmin):
    list_display = ['name', 'visitor_type', 'unit', 'status', 'expected_at', 'checked_in_at', 'is_walk_in']
    list_filter = ['status', 'visitor_type', 'community', 'is_walk_in']
    search_fields = ['name', 'phone', 'pass_code', 'vehicle_no']
    raw_id_fields = ['unit', 'created_by', 'responded_by']


@admin.register(SOSAlert)
class SOSAlertAdmin(admin.ModelAdmin):
    list_display = ['alert_type', 'unit', 'status', 'raised_by', 'created_at']
    list_filter = ['status', 'alert_type', 'community']


admin.site.register(FrequentEntry)
admin.site.register(KidExitPermission)


@admin.register(Incident)
class IncidentAdmin(admin.ModelAdmin):
    list_display = ['title', 'community', 'severity', 'status', 'created_at']
    list_filter = ['status', 'severity', 'community']


admin.site.register(GuardShift)
admin.site.register(VehicleLog)
admin.site.register(StaffAttendance)
admin.site.register(GateEvent)
