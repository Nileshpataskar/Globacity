"""python manage.py fresh_start — wipe all demo/user data and create one clean community.

Keeps master data (currencies, countries, cities, default help-desk categories) and the
`admin` superuser. Everything else (communities, residents, visitors, invoices, posts...)
is deleted. Then creates Globacity Residency (Pune, India) with Tower A and Tower B.
"""

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.db import transaction

from rest_framework_simplejwt.token_blacklist.models import OutstandingToken

from apps.accounts.models import OTPCode, User
from apps.communities.models import Community, Gate, Tower, Unit
from apps.locations.models import City, Country

COMMUNITY = 'Globacity Residency'
CITY, STATE, COUNTRY_ISO = 'Pune', 'Maharashtra', 'IN'
TOWERS = ['Tower A', 'Tower B']
FLOORS = 5
UNITS_PER_FLOOR = 4
ADMIN_USERNAME, ADMIN_PASSWORD = 'admin', 'admin123'


class Command(BaseCommand):
    help = 'Delete all demo data and create one community with two towers.'

    def add_arguments(self, parser):
        parser.add_argument('--yes', action='store_true', help='Skip the confirmation prompt')

    def handle(self, *args, **opts):
        if not opts['yes'] and input('This deletes ALL users (except admin) and communities. Type "yes": ') != 'yes':
            self.stdout.write('Cancelled.')
            return

        # Make sure master data (countries, currencies, cities, categories) exists.
        if not Country.objects.filter(iso2=COUNTRY_ISO).exists():
            call_command('seed_demo', '--force')

        with transaction.atomic():
            Community.objects.all().delete()  # cascades to towers, units, members, visitors, bills, posts...
            User.objects.exclude(phone=ADMIN_USERNAME).delete()  # cascades to devices, notifications...
            OTPCode.objects.all().delete()
            OutstandingToken.objects.all().delete()  # logs out every old session

            admin, _ = User.objects.get_or_create(phone=ADMIN_USERNAME, defaults={'full_name': 'Admin'})
            admin.is_staff = admin.is_superuser = admin.is_active = True
            admin.set_password(ADMIN_PASSWORD)
            admin.save()

            country = Country.objects.get(iso2=COUNTRY_ISO)
            city, _ = City.objects.get_or_create(country=country, name=CITY, defaults={'state': STATE})
            community = Community.objects.create(
                city=city, name=COMMUNITY, slug='globacity-residency', address=f'{CITY}, {STATE}',
            )
            for name in TOWERS:
                tower = Tower.objects.create(community=community, name=name, code=name[-1], floors=FLOORS)
                Unit.objects.bulk_create(
                    Unit(tower=tower, number=f'{floor}{i:02d}', floor=floor)
                    for floor in range(1, FLOORS + 1)
                    for i in range(1, UNITS_PER_FLOOR + 1)
                )
            Gate.objects.create(community=community, name='Main Gate')

        self.stdout.write(self.style.SUCCESS(
            f'Done. {COMMUNITY} ({CITY}) with {", ".join(TOWERS)} — '
            f'{Unit.objects.count()} flats. Admin login: {ADMIN_USERNAME} / {ADMIN_PASSWORD}'
        ))
