from django.contrib import admin

from .models import Ticket, TicketAttachment, TicketCategory, TicketUpdate


class UpdateInline(admin.TabularInline):
    model = TicketUpdate
    extra = 0


class AttachmentInline(admin.TabularInline):
    model = TicketAttachment
    extra = 0


@admin.register(Ticket)
class TicketAdmin(admin.ModelAdmin):
    list_display = ['number', 'title', 'community', 'unit', 'priority', 'status', 'created_at']
    list_filter = ['status', 'priority', 'community', 'category']
    search_fields = ['number', 'title']
    raw_id_fields = ['unit', 'raised_by']
    inlines = [UpdateInline, AttachmentInline]


@admin.register(TicketCategory)
class TicketCategoryAdmin(admin.ModelAdmin):
    list_display = ['name', 'community', 'sla_hours', 'is_active']
