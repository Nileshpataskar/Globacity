"""python manage.py bootstrap — master data + admin login for a fresh deployment. Safe to run on every start.

Creates (only if missing) currencies, countries, cities and default help-desk categories, and the platform
admin from ADMIN_USERNAME / ADMIN_PASSWORD. No demo communities or users are created.
"""

import os

from django.core.management.base import BaseCommand
from django.db import transaction

from apps.accounts.models import User
from apps.helpdesk.models import TicketCategory
from apps.locations.models import City, Country, Currency

from .seed_demo import COUNTRIES, CURRENCIES, TICKET_CATEGORIES


class Command(BaseCommand):
    help = 'Create master data and the admin login if they are missing.'

    @transaction.atomic
    def handle(self, *args, **opts):
        for code, name, symbol, dp in CURRENCIES:
            Currency.objects.get_or_create(code=code, defaults={'name': name, 'symbol': symbol, 'decimal_places': dp})
        for spec in COUNTRIES:
            spec = dict(spec)
            cities = spec.pop('cities')
            country, _ = Country.objects.get_or_create(iso2=spec['iso2'], defaults=spec)
            for city, state in cities:
                City.objects.get_or_create(country=country, name=city, defaults={'state': state})
        for name, icon in TICKET_CATEGORIES:
            TicketCategory.objects.get_or_create(community=None, name=name, defaults={'icon': icon})

        username = os.environ.get('ADMIN_USERNAME', 'admin')
        password = os.environ.get('ADMIN_PASSWORD')
        admin = User.objects.filter(phone=username).first()
        if admin is None and password:
            admin = User.objects.create(phone=username, full_name='Admin', is_staff=True, is_superuser=True)
            admin.set_password(password)
            admin.save()
            self.stdout.write(self.style.SUCCESS(f'Created admin login "{username}".'))
        elif admin is None:
            self.stdout.write(self.style.WARNING('ADMIN_PASSWORD not set: no admin login created.'))
        self.stdout.write(self.style.SUCCESS('Bootstrap done.'))
