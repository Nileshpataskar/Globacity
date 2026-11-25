"""python manage.py seed_demo — loads master data plus two demo communities in different countries."""

from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.communities.models import Community, EmergencyContact, Gate, Membership, StaffMember, Tower, Unit
from apps.engagement.models import (
    Classified,
    Event,
    EventRSVP,
    ForumPost,
    ForumReply,
    Notice,
    Poll,
    PollOption,
    PollVote,
    ServiceVendor,
)
from apps.finance.models import ChargeType, Payment, PaymentAllocation
from apps.finance.services import build_invoice, complete_payment, new_payment_reference
from apps.gate.models import FrequentEntry, Incident, Visitor
from apps.gate.services import new_pass_code
from apps.helpdesk.models import Ticket, TicketCategory, TicketUpdate
from apps.household.models import (
    DailyHelp,
    DailyHelpAssignment,
    DailyHelpAttendance,
    DailyHelpReview,
    FamilyMember,
    Pet,
    Vehicle,
)
from apps.locations.models import City, Country, Currency

CURRENCIES = [
    ('AED', 'UAE Dirham', 'د.إ', 2), ('INR', 'Indian Rupee', '₹', 2), ('SAR', 'Saudi Riyal', '﷼', 2),
    ('GBP', 'Pound Sterling', '£', 2), ('USD', 'US Dollar', '$', 2), ('KWD', 'Kuwaiti Dinar', 'د.ك', 3),
]

COUNTRIES = [
    dict(name='United Arab Emirates', iso2='AE', phone_code='+971', phone_number_length=9, currency_id='AED',
         timezone='Asia/Dubai', default_language='en', supported_languages=['en', 'ar'], tax_name='VAT',
         tax_rate=Decimal('5'), emergency_numbers={'police': '999', 'ambulance': '998', 'fire': '997'},
         cities=[('Dubai', 'Dubai'), ('Abu Dhabi', 'Abu Dhabi'), ('Sharjah', 'Sharjah')]),
    dict(name='India', iso2='IN', phone_code='+91', phone_number_length=10, currency_id='INR', timezone='Asia/Kolkata',
         default_language='en', supported_languages=['en', 'hi'], tax_name='GST', tax_rate=Decimal('18'),
         emergency_numbers={'emergency': '112', 'police': '100', 'ambulance': '102', 'fire': '101'},
         cities=[('Mumbai', 'Maharashtra'), ('Pune', 'Maharashtra'), ('Bengaluru', 'Karnataka')]),
    dict(name='Saudi Arabia', iso2='SA', phone_code='+966', phone_number_length=9, currency_id='SAR',
         timezone='Asia/Riyadh', default_language='ar', supported_languages=['ar', 'en'], tax_name='VAT',
         tax_rate=Decimal('15'), emergency_numbers={'police': '999', 'ambulance': '997', 'fire': '998'},
         cities=[('Riyadh', 'Riyadh'), ('Jeddah', 'Makkah')]),
    dict(name='United Kingdom', iso2='GB', phone_code='+44', phone_number_length=10, currency_id='GBP',
         timezone='Europe/London', default_language='en', supported_languages=['en'], tax_name='VAT',
         tax_rate=Decimal('20'), emergency_numbers={'emergency': '999'}, cities=[('London', 'England')]),
]

TICKET_CATEGORIES = [('Plumbing', 'plumbing'), ('Electrical', 'electrical'), ('AC / Cooling', 'ac_unit'),
                     ('Lift', 'elevator'), ('Housekeeping', 'cleaning'), ('Parking', 'parking'),
                     ('Complaint', 'report'), ('Other', 'more')]



class Command(BaseCommand):
    help = 'Seed countries, currencies and two demo communities (Dubai/AED and Mumbai/INR).'

    def add_arguments(self, parser):
        parser.add_argument('--force', action='store_true', help='Seed even if demo data already exists')

    def handle(self, *args, **opts):
        if Community.objects.filter(slug='palm-vista-residences').exists() and not opts['force']:
            self.stdout.write(self.style.WARNING('Demo data already present. Use --force to add again.'))
            return
        with transaction.atomic():
            self.seed()
        self.stdout.write(self.style.SUCCESS('Demo data loaded.'))
        self.stdout.write(
            '\nLogins (password login at /api/v1/auth/login/ or OTP for any phone):\n'
            '  Platform admin   +971500000001  Admin@12345   (also Django admin at /admin/)\n'
            '  Community admin  +971500000002  Manager@12345 (Palm Vista, Dubai)\n'
            '  Community admin  +919800000002  Manager@12345 (Sea Breeze, Mumbai)\n'
            '  Guard            +971500000003  Guard@12345   (Palm Vista)\n'
            '  Resident         +971501234567  (OTP login)   units in Dubai (AED) and Mumbai (INR)\n'
        )

    # ------------------------------------------------------------------

    def user(self, phone, name, password=None, **extra):
        u, created = User.objects.get_or_create(phone=phone, defaults={'full_name': name, **extra})
        if created and password:
            u.set_password(password)
            u.save()
        return u

    def seed(self):
        now = timezone.now()
        for code, name, symbol, dp in CURRENCIES:
            Currency.objects.update_or_create(code=code, defaults={'name': name, 'symbol': symbol, 'decimal_places': dp})
        cities = {}
        for spec in COUNTRIES:
            spec = dict(spec)
            city_specs = spec.pop('cities')
            country, _ = Country.objects.update_or_create(iso2=spec['iso2'], defaults=spec)
            for cname, state in city_specs:
                cities[cname], _ = City.objects.get_or_create(country=country, name=cname, defaults={'state': state})
        for name, icon in TICKET_CATEGORIES:
            TicketCategory.objects.get_or_create(community=None, name=name, defaults={'icon': icon})

        uae = Country.objects.get(iso2='AE')
        india = Country.objects.get(iso2='IN')

        # Users -----------------------------------------------------------------
        self.user('+971500000001', 'Platform Admin', 'Admin@12345', is_staff=True, is_superuser=True, country=uae)
        dubai_admin = self.user('+971500000002', 'Grace Lim', 'Manager@12345', country=uae, email='grace@example.com')
        mumbai_admin = self.user('+919800000002', 'Rahul Verma', 'Manager@12345', country=india)
        guard = self.user('+971500000003', 'Joseph Mathew', 'Guard@12345', country=uae)
        aarav = self.user('+971501234567', 'Aarav Mehta', country=uae, email='aarav@example.com')
        neighbours = [self.user(p, n, country=uae) for p, n in [
            ('+971501112233', 'Meera Shah'), ('+971554445566', 'John Davis'), ('+971527778899', 'Lina Haddad'),
            ('+971561239876', 'Omar Khalid'), ('+971552221100', 'Sara Ahmed')]]

        # Communities -----------------------------------------------------------
        palm = Community.objects.create(
            city=cities['Dubai'], name='Palm Vista Residences', slug='palm-vista-residences',
            address='Jumeirah Village Circle, Dubai', contact_phone='+97145550101',
            contact_email='office@palmvista.example', primary_color='#2563EB')
        sea = Community.objects.create(
            city=cities['Mumbai'], name='Sea Breeze Towers', slug='sea-breeze-towers', address='Bandra West, Mumbai',
            contact_phone='+912226550101', primary_color='#0EA5A4')

        def build(community, towers, floors, per_floor):
            result = {}
            for t in towers:
                tower = Tower.objects.create(community=community, name=t, floors=floors)
                Unit.objects.bulk_create([Unit(tower=tower, number=f'{f}{i:02d}', floor=f)
                                          for f in range(1, floors + 1) for i in range(1, per_floor + 1)])
                result[t] = tower
            return result

        palm_towers = build(palm, ['Tower A', 'Tower B', 'Tower C'], 15, 4)
        sea_towers = build(sea, ['Tower 1', 'Tower 2'], 10, 4)
        main_gate = Gate.objects.create(community=palm, name='Main Gate', iot_enabled=True, iot_device_id='BOOM-PV-01')
        Gate.objects.create(community=palm, name='Service Gate')
        Gate.objects.create(community=sea, name='Main Gate')

        unit = lambda tower, n: Unit.objects.get(tower=tower, number=n)  # noqa: E731
        b1204 = unit(palm_towers['Tower B'], '1204')
        t803 = unit(sea_towers['Tower 1'], '803')

        StaffMember.objects.bulk_create([
            StaffMember(community=palm, user=dubai_admin, name='Grace Lim', phone=dubai_admin.phone, role='admin',
                        designation='Community Manager'),
            StaffMember(community=palm, user=guard, name='Joseph Mathew', phone=guard.phone, role='guard',
                        designation='Security Supervisor', shift='Day shift'),
            StaffMember(community=palm, name='Imran Sheikh', phone='+97145550102', role='manager',
                        designation='Facility Manager'),
            StaffMember(community=palm, name='Abdul Rahman', phone='+97145550103', role='facility',
                        designation='Electrician', shift='On call'),
            StaffMember(community=palm, name='Suresh Pillai', phone='+97145550104', role='facility',
                        designation='Plumber', shift='On call'),
            StaffMember(community=sea, user=mumbai_admin, name='Rahul Verma', phone=mumbai_admin.phone, role='admin',
                        designation='Society Secretary'),
        ])

        approved = dict(status=Membership.Status.APPROVED, approved_at=now, approved_by=dubai_admin)
        Membership.objects.create(user=aarav, unit=b1204, role='owner', **approved)
        Membership.objects.create(user=aarav, unit=t803, role='tenant', status='approved', approved_at=now,
                                  approved_by=mumbai_admin)
        for u, (t, n) in zip(neighbours, [('Tower B', '904'), ('Tower A', '301'), ('Tower A', '1502'),
                                          ('Tower C', '203'), ('Tower C', '1101')]):
            Membership.objects.create(user=u, unit=unit(palm_towers[t], n), role='owner', **approved)
        pending = self.user('+971509990000', 'New Resident', country=uae)
        Membership.objects.create(user=pending, unit=unit(palm_towers['Tower A'], '1001'), role='tenant')

        EmergencyContact.objects.bulk_create([
            EmergencyContact(community=palm, name='Security Control Room', phone='+97145550199', icon='shield', order=0),
            EmergencyContact(community=palm, name='Facility Management', phone='+97145550101', icon='engineering', order=1),
            EmergencyContact(user=aarav, group='personal', name='Priya Mehta (Spouse)', phone='+971507654321',
                             icon='favorite'),
        ])

        # Household -------------------------------------------------------------
        FamilyMember.objects.bulk_create([
            FamilyMember(unit=b1204, name='Priya Mehta', relation='Spouse', phone='+971507654321'),
            FamilyMember(unit=b1204, name='Kabir Mehta', relation='Son', is_minor=True),
            FamilyMember(unit=b1204, name='Anaya Mehta', relation='Daughter', is_minor=True),
        ])
        Vehicle.objects.bulk_create([
            Vehicle(unit=b1204, number='Dubai A 12345', make_model='Toyota Land Cruiser', color='White',
                    parking_slot='B2-118'),
            Vehicle(unit=b1204, number='Dubai K 90876', make_model='Tesla Model 3', color='Grey', parking_slot='B2-119'),
        ])
        Pet.objects.create(unit=b1204, name='Bruno', species='Dog', breed='Golden Retriever', vaccinated=True)

        today = timezone.localdate()
        helpers = []
        for name, role, phone, timing in [('Fatima Noor', 'Housekeeping', '+971562223344', '9:00 AM - 1:00 PM'),
                                          ('Ramesh Kumar', 'Driver', '+971557778899', '7:30 AM - 7:00 PM'),
                                          ('Maria Santos', 'Nanny', '+971521110099', '8:00 AM - 6:00 PM')]:
            h = DailyHelp.objects.create(community=palm, name=name, role=role, phone=phone, id_verified=True,
                                         pass_code=new_pass_code(palm))
            DailyHelpAssignment.objects.create(helper=h, unit=b1204, timing=timing, added_by=aarav)
            for d in range(1, today.day + 1):
                if d % 7 in (3, 4):
                    continue
                day = today.replace(day=d)
                start = timezone.make_aware(timezone.datetime(day.year, day.month, day.day, 5, 0))
                DailyHelpAttendance.objects.create(helper=h, date=day, check_in=start, gate=main_gate,
                                                   check_out=None if d == today.day and name == 'Fatima Noor'
                                                   else start + timedelta(hours=4))
            helpers.append(h)
        DailyHelpAssignment.objects.create(helper=helpers[0], unit=unit(palm_towers['Tower B'], '904'),
                                           timing='2:00 PM - 5:00 PM')
        DailyHelpReview.objects.create(helper=helpers[0], author=neighbours[0], unit=unit(palm_towers['Tower B'], '904'),
                                       rating=5, comment='Very punctual and thorough.')
        DailyHelpReview.objects.create(helper=helpers[1], author=aarav, unit=b1204, rating=5,
                                       comment='Safe driver, always on time.')

        # Gate ------------------------------------------------------------------
        def visitor(**kw):
            kw.setdefault('pass_code', new_pass_code(palm))
            return Visitor.objects.create(community=palm, unit=b1204, **kw)

        visitor(name='Talabat Delivery', visitor_type='delivery', company='Talabat', status='waiting', is_walk_in=True,
                created_by=guard, gate=main_gate, pass_code='')
        visitor(name='Rohan Kapoor', visitor_type='guest', phone='+971523349981', guests=3, status='expected',
                expected_at=now + timedelta(hours=3), valid_until=now + timedelta(hours=15), created_by=aarav)
        visitor(name='Careem', visitor_type='cab', company='Careem', vehicle_no='D 48213', status='expected',
                expected_at=now + timedelta(minutes=40), valid_until=now + timedelta(hours=6), created_by=aarav)
        visitor(name='AC Service - CoolTech', visitor_type='service', company='CoolTech', status='inside',
                checked_in_at=now - timedelta(minutes=45), created_by=aarav, gate=main_gate)
        visitor(name='Amazon Delivery', visitor_type='delivery', company='Amazon', status='exited', pass_code='',
                checked_in_at=now - timedelta(days=1, hours=3), checked_out_at=now - timedelta(days=1, hours=2))
        visitor(name='Sara Ahmed', visitor_type='guest', guests=2, status='exited', created_by=aarav,
                checked_in_at=now - timedelta(days=2), checked_out_at=now - timedelta(days=2) + timedelta(hours=3))
        FrequentEntry.objects.create(unit=b1204, name='Milk delivery - Al Rawabi', visitor_type='delivery',
                                     company='Al Rawabi', valid_from=today, valid_until=today + timedelta(days=60),
                                     pass_code=new_pass_code(palm), created_by=aarav)

        # Finance (each community bills in its own currency and tax) -------------
        for community, u, admin in [(palm, b1204, dubai_admin), (sea, t803, mumbai_admin)]:
            amounts = {'AED': (2450, 612.40, 150), 'INR': (18500, 2400, 1200)}[community.currency.code]
            service = ChargeType.objects.create(community=community, name='Service charges', frequency='quarterly',
                                                default_amount=amounts[0])
            utility = ChargeType.objects.create(community=community,
                                                name='Chiller (district cooling)' if community == palm else 'Water charges',
                                                default_amount=amounts[1])
            ChargeType.objects.create(community=community, name='Clubhouse booking', frequency='one_time',
                                      default_amount=amounts[2], is_taxable=False)
            paid = build_invoice(community=community, unit=u, title=service.name, amount=service.default_amount,
                                 due_date=today - timedelta(days=95), period_label='Q3 2026', charge_type=service,
                                 issued_by=admin)
            paid.save()
            payment = Payment.objects.create(community=community, unit=u, user=aarav, reference=new_payment_reference(),
                                             currency=paid.currency, amount=paid.total, method='card', gateway='mock')
            PaymentAllocation.objects.create(payment=payment, invoice=paid, amount=paid.total)
            complete_payment(payment, True, 'MOCK-SEED')
            for title, amount, due, period, ct in [
                (service.name, service.default_amount, today + timedelta(days=9), 'Q4 2026', service),
                (utility.name, utility.default_amount, today - timedelta(days=3), 'September 2026', utility),
            ]:
                build_invoice(community=community, unit=u, title=title, amount=amount, due_date=due, period_label=period,
                              charge_type=ct, issued_by=admin).save()

        # Community -------------------------------------------------------------
        notices = [
            ('Water supply interruption - Tower B', 'Water supply to Tower B will be interrupted on Saturday from '
             '10:00 AM to 2:00 PM for tank maintenance. Please store water in advance.', 'Maintenance', True),
            ('Annual General Meeting 2026', 'All owners are invited to the AGM at the Clubhouse on 2 November at '
             '7:00 PM. Agenda: budget approval, committee elections and parking policy.', 'Meeting', False),
            ('Pool closed for deep cleaning', 'The swimming pool will remain closed Monday to Wednesday.', 'Amenities',
             False),
            ('Fire drill this Thursday', 'A mandatory fire drill will be held on Thursday at 11:00 AM.', 'Safety', False),
        ]
        for i, (title, body, cat, pinned) in enumerate(notices):
            Notice.objects.create(community=palm, title=title, body=body, category=cat, is_pinned=pinned,
                                  published_at=now - timedelta(days=i, hours=5), posted_by=dubai_admin,
                                  author_label='Facility Management')
        Notice.objects.create(community=sea, title='Society maintenance due', body='Quarterly maintenance is due.',
                              category='Finance', published_at=now, posted_by=mumbai_admin, author_label='Committee')

        for question, options, days, votes in [
            ('Should we extend gym hours to 24/7?', ['Yes, 24/7', 'Extend to midnight only', 'Keep current hours'], 4,
             [0, 0, 1, 2, 0]),
            ('Preferred date for the Diwali celebration?', ['Fri, 6 Nov', 'Sat, 7 Nov'], 2, [1, 1, 0]),
        ]:
            poll = Poll.objects.create(community=palm, question=question, closes_at=now + timedelta(days=days),
                                       created_by=dubai_admin)
            opts = [PollOption.objects.create(poll=poll, label=label, order=i) for i, label in enumerate(options)]
            for voter, choice in zip(neighbours, votes):
                m = voter.memberships.first()
                PollVote.objects.create(poll=poll, option=opts[choice], user=voter, unit=m.unit)

        events = [
            ('Diwali Night Celebration', 'Lights, music, food stalls and a kids rangoli competition.', 21, 'Central Lawn',
             'Festival'),
            ('Sunrise Yoga', 'Free weekend yoga session for all levels.', 2, 'Rooftop Deck, Tower A', 'Fitness'),
            ('Kids Football Tournament', 'Under-12 inter-tower football tournament.', 9, 'Sports Court', 'Sports'),
        ]
        for title, desc, days, venue, cat in events:
            e = Event.objects.create(community=palm, title=title, description=desc, venue=venue, category=cat,
                                     starts_at=now + timedelta(days=days), created_by=dubai_admin)
            for voter in neighbours[:3]:
                EventRSVP.objects.create(event=e, user=voter, unit=voter.memberships.first().unit, guests=2)

        post = ForumPost.objects.create(community=palm, unit=unit(palm_towers['Tower B'], '904'), author=neighbours[0],
                                        title='Recommendations for a good AC technician?', tag='Recommendations',
                                        body='Our AC is making a loud noise. Any reliable technician?')
        ForumReply.objects.create(post=post, author=neighbours[1], body='CoolTech did a great job for us.')
        ForumPost.objects.create(community=palm, unit=unit(palm_towers['Tower C'], '203'), author=neighbours[3],
                                 title='Carpool to DIFC on weekdays', tag='Carpool',
                                 body='Leaving at 7:45 AM daily. Two seats available.')

        for seller, title, price, cat in [(neighbours[1], 'IKEA 3-seater sofa', 650, 'Furniture'),
                                          (neighbours[0], 'Kids bicycle (16")', 180, 'Kids'),
                                          (neighbours[3], 'PlayStation 5 + 2 controllers', 1500, 'Electronics')]:
            Classified.objects.create(community=palm, unit=seller.memberships.first().unit, seller=seller, title=title,
                                      price=price, currency=palm.currency, category=cat, description=title)

        for name, cat, price, eta in [('SparkleClean Services', 'Cleaning', 99, 'Today'),
                                      ('CoolTech AC Repairs', 'AC Repair', 149, '2 hrs'),
                                      ('FixIt Plumbing', 'Plumbing', 120, 'Today'),
                                      ('Fresh Basket Grocery', 'Grocery', 0, '30 min')]:
            ServiceVendor.objects.create(community=palm, name=name, category=cat, price_from=price, eta_text=eta,
                                         currency=palm.currency)

        plumbing = TicketCategory.objects.get(community=None, name='Plumbing')
        t = Ticket.objects.create(community=palm, unit=b1204, raised_by=aarav, category=plumbing, number='T-1001',
                                  title='Water leakage in kitchen sink', priority='high', status='in_progress',
                                  description='Water is leaking from under the kitchen sink pipe joint.',
                                  assigned_to=StaffMember.objects.get(community=palm, name='Suresh Pillai'))
        TicketUpdate.objects.create(ticket=t, author=aarav, message='Ticket raised', status_change='open')
        TicketUpdate.objects.create(ticket=t, author=dubai_admin, message='Assigned to Suresh Pillai')
        TicketUpdate.objects.create(ticket=t, author=dubai_admin, message='Technician visit scheduled for 4:00 PM',
                                    status_change='in_progress')
        Incident.objects.create(community=palm, reported_by=guard, title='Unattended bag near lobby',
                                description='Black backpack left near Tower A lobby entrance.', category='Security',
                                severity='medium', location='Tower A lobby')
