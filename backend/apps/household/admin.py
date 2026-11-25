from django.contrib import admin

from .models import DailyHelp, DailyHelpAssignment, DailyHelpAttendance, DailyHelpReview, FamilyMember, Pet, Vehicle


class AssignmentInline(admin.TabularInline):
    model = DailyHelpAssignment
    extra = 0
    raw_id_fields = ['unit', 'added_by']


@admin.register(DailyHelp)
class DailyHelpAdmin(admin.ModelAdmin):
    list_display = ['name', 'role', 'phone', 'community', 'id_verified', 'is_active']
    list_filter = ['community', 'role', 'id_verified']
    search_fields = ['name', 'phone']
    inlines = [AssignmentInline]


@admin.register(FamilyMember)
class FamilyMemberAdmin(admin.ModelAdmin):
    list_display = ['name', 'relation', 'unit', 'is_minor']
    raw_id_fields = ['unit']


@admin.register(Vehicle)
class VehicleAdmin(admin.ModelAdmin):
    list_display = ['number', 'make_model', 'unit', 'parking_slot']
    search_fields = ['number']
    raw_id_fields = ['unit']


admin.site.register(Pet)
admin.site.register(DailyHelpAttendance)
admin.site.register(DailyHelpReview)
