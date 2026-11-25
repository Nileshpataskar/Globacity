from django.contrib import admin

from .models import (
    Classified,
    Event,
    EventRSVP,
    ForumPost,
    ForumReply,
    MoveDocument,
    MoveRequest,
    Notice,
    Poll,
    PollOption,
    ServiceBooking,
    ServiceVendor,
)


@admin.register(Notice)
class NoticeAdmin(admin.ModelAdmin):
    list_display = ['title', 'community', 'category', 'is_pinned', 'published_at']
    list_filter = ['community', 'category', 'is_pinned']
    search_fields = ['title']


class PollOptionInline(admin.TabularInline):
    model = PollOption
    extra = 2


@admin.register(Poll)
class PollAdmin(admin.ModelAdmin):
    list_display = ['question', 'community', 'closes_at']
    inlines = [PollOptionInline]


@admin.register(Event)
class EventAdmin(admin.ModelAdmin):
    list_display = ['title', 'community', 'starts_at', 'venue']
    list_filter = ['community', 'category']


class ReplyInline(admin.TabularInline):
    model = ForumReply
    extra = 0


@admin.register(ForumPost)
class ForumPostAdmin(admin.ModelAdmin):
    list_display = ['title', 'author', 'community', 'is_locked', 'created_at']
    inlines = [ReplyInline]


class MoveDocumentInline(admin.TabularInline):
    model = MoveDocument
    extra = 0


@admin.register(MoveRequest)
class MoveRequestAdmin(admin.ModelAdmin):
    list_display = ['unit', 'move_type', 'move_date', 'status']
    list_filter = ['status', 'move_type']
    inlines = [MoveDocumentInline]


admin.site.register(EventRSVP)
admin.site.register(Classified)
admin.site.register(ServiceVendor)
admin.site.register(ServiceBooking)
