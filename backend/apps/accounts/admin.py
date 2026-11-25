from django.contrib import admin
from django.contrib.auth.admin import UserAdmin as BaseUserAdmin

from .models import OTPCode, User, UserSettings


@admin.register(User)
class UserAdmin(BaseUserAdmin):
    ordering = ['full_name']
    list_display = ['phone', 'full_name', 'email', 'country', 'is_staff', 'is_active', 'date_joined']
    list_filter = ['is_staff', 'is_superuser', 'is_active', 'country']
    search_fields = ['phone', 'full_name', 'email']
    fieldsets = (
        (None, {'fields': ('phone', 'password')}),
        ('Profile', {'fields': ('full_name', 'email', 'avatar', 'country', 'language')}),
        ('Permissions', {'fields': ('is_active', 'is_staff', 'is_superuser', 'groups', 'user_permissions')}),
        ('Dates', {'fields': ('last_login', 'date_joined')}),
    )
    add_fieldsets = ((None, {'classes': ('wide',), 'fields': ('phone', 'full_name', 'password1', 'password2')}),)


admin.site.register(UserSettings)


@admin.register(OTPCode)
class OTPCodeAdmin(admin.ModelAdmin):
    list_display = ['phone', 'created_at', 'expires_at', 'attempts', 'is_used']
    readonly_fields = ['phone', 'code_hash', 'expires_at', 'attempts', 'is_used', 'created_at']
