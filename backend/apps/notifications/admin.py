from django.contrib import admin

from .models import Device, Notification


@admin.register(Notification)
class NotificationAdmin(admin.ModelAdmin):
    list_display = ['title', 'user', 'category', 'is_read', 'created_at']
    list_filter = ['category', 'is_read']
    search_fields = ['title', 'user__phone', 'user__full_name']


@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ['user', 'platform', 'created_at']
