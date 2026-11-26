"""python manage.py seed_india — realistic Indian sample data for every community and tower.

Adds, per tower: ~7 residents (owners / tenants) + 1 pending request, families, vehicles, maintenance bills
(paid / overdue / upcoming), visitors, help-desk tickets. Per community: manager + guards + facility staff,
charge types, notices, polls with votes, events with RSVPs, daily help, vendors, forum posts, classifieds,
emergency contacts, a move-in request and an incident.

Sample people use phone numbers +9190000xxxxx. A community is seeded once (marked in its settings).
  --community <id>   only that community        --remove   delete all sample data again
"""

import random
from datetime import timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from apps.accounts.models import User
from apps.communities.models import Community, EmergencyContact, Gate, Membership, StaffMember, Unit
from apps.engagement.models import (
    Classified, Event, EventRSVP, ForumPost, ForumReply, MoveRequest, Notice, Poll, PollOption, PollVote, ServiceVendor,
)
from apps.finance.models import ChargeType, Invoice, Payment, PaymentAllocation
from apps.finance.services import build_invoice, complete_payment, new_payment_reference
from apps.gate.models import Incident, Visitor
from apps.gate.services import new_pass_code
from apps.helpdesk.models import Ticket, TicketCategory, TicketUpdate
from apps.helpdesk.views import next_ticket_number
from apps.household.models import DailyHelp, DailyHelpAssignment, DailyHelpAttendance, FamilyMember, Vehicle

PHONE_PREFIX = '+9190000'
MARK = 'sample_data_india'

FIRST = ['Aarav', 'Vivaan', 'Aditya', 'Rohan', 'Arjun', 'Kabir', 'Ishaan', 'Siddharth', 'Rahul', 'Nikhil', 'Pranav',
         'Omkar', 'Sanket', 'Tejas', 'Amit', 'Vikram', 'Priya', 'Ananya', 'Sneha', 'Pooja', 'Neha', 'Kavya', 'Meera',
         'Shruti', 'Aditi', 'Riya', 'Sakshi', 'Prachi', 'Gauri', 'Anjali', 'Rutuja', 'Swati']
LAST = ['Kulkarni', 'Deshpande', 'Joshi', 'Patil', 'Shinde', 'Jadhav', 'Pawar', 'Gokhale', 'Sharma', 'Verma', 'Iyer',
        'Nair', 'Reddy', 'Mehta', 'Shah', 'Gupta', 'Agarwal', 'Bhosale', 'Chavan', 'Kapoor', 'Malhotra', 'Rao', 'Menon',
        'Saxena', 'Banerjee', 'Mukherjee', 'Desai', 'Naik']
CARS = [('Maruti Suzuki Swift', 'White'), ('Hyundai Creta', 'Grey'), ('Tata Nexon EV', 'Blue'), ('Honda City', 'Silver'),
        ('Mahindra XUV700', 'Black'), ('Kia Seltos', 'Red'), ('Toyota Innova Crysta', 'White')]
BIKES = [('Honda Activa 6G', 'Grey'), ('Royal Enfield Classic 350', 'Black'), ('TVS Jupiter', 'Blue'),
         ('Ather 450X', 'White')]


class Command(BaseCommand):
    help = 'Fill every community with realistic Indian sample data.'

    def add_arguments(self, parser):
        parser.add_argument('--community', help='Only this community id')
        parser.add_argument('--remove', action='store_true', help='Delete the sample data instead')

    def handle(self, *args, **opts):
        communities = Community.objects.select_related('city__country__currency')
        if opts['community']:
            communities = communities.filter(pk=opts['community'])
        if opts['remove']:
            return self.remove(communities)
        for c in communities:
            if (c.settings or {}).get(MARK):
                self.stdout.write(f'Skipping {c.name}: sample data already added.')
                continue
            if not c.towers.filter(units__isnull=False).exists():
                self.stdout.write(self.style.WARNING(f'Skipping {c.name}: it has no towers with flats yet.'))
                continue
            with transaction.atomic():
                self.seed(c)
                c.settings = {**(c.settings or {}), MARK: True}
                c.save(update_fields=['settings'])
            self.stdout.write(self.style.SUCCESS(f'Added sample data to {c.name}.'))

    # ------------------------------------------------------------------ helpers

    def person(self, name):
        """Sample user with a unique +9190000xxxxx number."""
        while True:
            phone = f'{PHONE_PREFIX}{self.rng.randint(0, 99999):05d}'
            if not User.objects.filter(phone=phone).exists():
                return User.objects.create(phone=phone, full_name=name, country=self.country)

    def name(self):
        return f'{self.rng.choice(FIRST)} {self.rng.choice(LAST)}'

    def at(self, days=0, hours=0, minutes=0):
        return self.now + timedelta(days=days, hours=hours, minutes=minutes)

    # ------------------------------------------------------------------ seed one community

    def seed(self, c):
        self.rng = random.Random(str(c.pk))
        self.now = timezone.now()
        self.country = c.city.country
        today = timezone.localdate()
        cur = c.currency
        towers = list(c.towers.filter(units__isnull=False).distinct().order_by('name'))
        gate = c.gates.filter(is_active=True).first() or Gate.objects.create(community=c, name='Main Gate')

        # Staff -------------------------------------------------------------------------------------
        manager_user = self.person(self.name())
        StaffMember.objects.create(community=c, user=manager_user, name=manager_user.full_name, phone=manager_user.phone,
                                   role='manager', designation='Society Manager')
        guards = []
        for shift in ['Day shift (8 AM – 8 PM)', 'Night shift (8 PM – 8 AM)']:
            g = self.person(f'{self.rng.choice(["Ramesh", "Sunil", "Santosh", "Mahesh", "Dinesh"])} {self.rng.choice(["Yadav", "Kamble", "More", "Gaikwad"])}')
            StaffMember.objects.create(community=c, user=g, name=g.full_name, phone=g.phone, role='guard',
                                       designation='Security Guard', shift=shift)
            guards.append(g)
        facility = {}
        for designation, nm in [('Electrician', 'Prakash Salunkhe'), ('Plumber', 'Ganesh Wagh'),
                                ('Housekeeping Supervisor', 'Lata Sawant'), ('Lift Technician', 'Imran Shaikh')]:
            facility[designation] = StaffMember.objects.create(
                community=c, name=nm, phone=f'{PHONE_PREFIX}{self.rng.randint(0, 99999):05d}', role='facility',
                designation=designation, shift='On call')

        EmergencyContact.objects.bulk_create([
            EmergencyContact(community=c, name='Police', phone='112', icon='local_police', order=0),
            EmergencyContact(community=c, name='Ambulance', phone='108', icon='emergency', order=1),
            EmergencyContact(community=c, name='Fire Brigade', phone='101', icon='local_fire_department', order=2),
            EmergencyContact(community=c, name='Society Office', phone=manager_user.phone, icon='apartment', order=3),
            EmergencyContact(community=c, name='Security Cabin (Main Gate)', phone=guards[0].phone, icon='shield', order=4),
        ])

        # Residents per tower -----------------------------------------------------------------------
        residents = []  # (user, unit, membership)
        for tower in towers:
            units = list(tower.units.order_by('floor', 'number'))
            taken = {m.unit_id for m in Membership.objects.filter(unit__in=units)}
            free = [u for u in units if u.pk not in taken]
            step = max(1, len(free) // 8)
            picks = free[::step][:8]
            for i, unit in enumerate(picks):
                user = self.person(self.name())
                if i == len(picks) - 1 and len(picks) > 3:
                    Membership.objects.create(user=user, unit=unit, role='tenant', note='Moving in next month')
                    continue  # pending approval
                role = 'tenant' if i % 3 == 2 else 'owner'
                m = Membership.objects.create(user=user, unit=unit, role=role, status='approved',
                                              approved_at=self.at(days=-self.rng.randint(20, 300)), approved_by=manager_user)
                residents.append((user, unit, m))
                surname = user.full_name.split()[-1]
                if i % 2 == 0:
                    FamilyMember.objects.create(unit=unit, name=f'{self.rng.choice(["Priya", "Sneha", "Kavya", "Anjali"])} {surname}',
                                                relation='Spouse', phone=f'{PHONE_PREFIX}{self.rng.randint(0, 99999):05d}')
                    FamilyMember.objects.create(unit=unit, name=f'{self.rng.choice(["Arnav", "Myra", "Vihaan", "Saanvi"])} {surname}',
                                                relation=self.rng.choice(['Son', 'Daughter']), is_minor=True)
                if i % 3 != 1:
                    car, color = self.rng.choice(CARS)
                    Vehicle.objects.create(unit=unit, number=f'MH 12 {self.rng.choice("ABCDEFGHJK")}{self.rng.choice("ABCDEFGHJK")} {self.rng.randint(1000, 9999)}',
                                           make_model=car, color=color, parking_slot=f'P{self.rng.randint(1, 2)}-{self.rng.randint(1, 120)}')
                if i % 2 == 1:
                    bike, color = self.rng.choice(BIKES)
                    Vehicle.objects.create(unit=unit, vehicle_type='bike', make_model=bike, color=color,
                                           number=f'MH 12 {self.rng.choice("ABCDEFGHJK")}{self.rng.choice("ABCDEFGHJK")} {self.rng.randint(1000, 9999)}')
        if not residents:
            return

        # Finance -----------------------------------------------------------------------------------
        maint = ChargeType.objects.create(community=c, name='Monthly maintenance', frequency='monthly',
                                          default_amount=Decimal('3500'))
        water = ChargeType.objects.create(community=c, name='Water charges', frequency='monthly', default_amount=Decimal('450'))
        ChargeType.objects.create(community=c, name='Parking (extra slot)', frequency='monthly', default_amount=Decimal('500'))
        ChargeType.objects.create(community=c, name='Clubhouse booking', frequency='one_time', default_amount=Decimal('2000'),
                                  is_taxable=False)
        manager = manager_user
        this_month = today.replace(day=1)
        last_month = (this_month - timedelta(days=1)).replace(day=1)
        two_back = (last_month - timedelta(days=1)).replace(day=1)
        next_month = (this_month + timedelta(days=32)).replace(day=1)
        # (month, rule): 'all' = everyone paid, 'most' = ~1 in 4 flats unpaid (defaulters), 'none' = not due yet.
        schedule = [(two_back, 'all'), (last_month, 'most'), (this_month, 'most2'), (next_month, 'none')]
        invoices = []
        for idx, (user, unit, _) in enumerate(residents):
            for month, rule in schedule:
                label = month.strftime('%B %Y')
                for ct in (maint, water):
                    amount = ct.default_amount + (Decimal(unit.floor or 0) * 50 if ct == maint else 0)
                    inv = build_invoice(community=c, unit=unit, title=ct.name, amount=amount,
                                        due_date=month + timedelta(days=9), period_label=label, charge_type=ct,
                                        issued_by=manager, exclude_numbers={i.number for i in invoices})
                    inv.save()
                    invoices.append(inv)
                    paid = rule == 'all' or (rule == 'most' and idx % 4 != 3) or (rule == 'most2' and idx % 4 not in (2, 3))
                    if not paid:
                        continue
                    method = self.rng.choice(['google_pay', 'google_pay', 'bank_transfer', 'card', 'cash', 'cheque'])
                    p = Payment.objects.create(community=c, unit=unit, user=user, reference=new_payment_reference(),
                                               currency=inv.currency, amount=inv.total, method=method,
                                               gateway='mock' if method in ('google_pay', 'card') else 'offline')
                    PaymentAllocation.objects.create(payment=p, invoice=inv, amount=inv.total)
                    complete_payment(p, True, f'UPI{self.rng.randint(10**9, 10**10 - 1)}' if method == 'google_pay' else 'SEED')
                    paid_on = min(month + timedelta(days=self.rng.randint(1, 9)), today)
                    Payment.objects.filter(pk=p.pk).update(paid_at=timezone.make_aware(
                        timezone.datetime.combine(paid_on, timezone.datetime.min.time()) + timedelta(hours=self.rng.randint(8, 21))))

        # Notices -----------------------------------------------------------------------------------
        tower_names = ', '.join(t.name for t in towers)
        notices = [
            ('Water supply interruption on Saturday', 'Due to PMC pipeline maintenance, water supply will be off on '
             'Saturday from 10 AM to 4 PM. Please store water in advance. Tankers will be arranged if needed.',
             'Maintenance', True, towers[:1]),
            ('Diwali celebration 2026 🪔', 'Join us for Diwali Milan in the clubhouse lawn: rangoli competition, '
             'diya decoration for kids, and dinner. Contribution ₹500 per flat, payable at the society office.',
             'Event', True, []),
            ('Maintenance due by the 10th', 'Monthly maintenance and water charges are due by the 10th of every month. '
             'Pay via the app (UPI / card) to avoid a late fee of ₹100.', 'Finance', False, []),
            ('Pest control drive', 'Cockroach and termite treatment for common areas and flats on Sunday 9 AM onwards. '
             'Residents who want flat treatment may register with the security desk.', 'Maintenance', False, []),
            ('Lift maintenance', f'Lift servicing in {towers[-1].name} on Tuesday 11 AM – 1 PM. Please use the other lift '
             'or the stairs during this time.', 'Maintenance', False, towers[-1:]),
            ('Annual General Meeting', 'The AGM will be held in the clubhouse on Sunday at 6 PM. Agenda: audited '
             'accounts, CCTV upgrade, solar panels proposal and committee elections.', 'General', False, []),
            ('New parking stickers', f'Collect your 2027 parking stickers from the security cabin. Applies to {tower_names}. '
             'Vehicles without stickers will not be allowed inside after the 15th.', 'Security', False, []),
        ]
        for i, (title, body, cat, pinned, target) in enumerate(notices):
            n = Notice.objects.create(community=c, title=title, body=body, category=cat, is_pinned=pinned,
                                      published_at=self.at(days=-i * 2, hours=-3), posted_by=manager,
                                      author_label='Managing Committee')
            if target:
                n.target_towers.set(target)

        # Polls with votes --------------------------------------------------------------------------
        for question, options, days, desc in [
            ('Should we install rooftop solar panels?', ['Yes, go ahead', 'Need more details first', 'No'], 6,
             'Estimated cost ₹18 lakh, saving about ₹1.2 lakh per month on common-area electricity.'),
            ('Best date for Diwali Milan?', ['Saturday evening', 'Sunday evening'], 3, ''),
            ('Gym timings from next month', ['5 AM – 11 PM', '6 AM – 10 PM', '24 × 7 with access card'], 10, ''),
        ]:
            poll = Poll.objects.create(community=c, question=question, description=desc,
                                       closes_at=self.at(days=days), created_by=manager)
            opts = [PollOption.objects.create(poll=poll, label=label, order=i) for i, label in enumerate(options)]
            for user, unit, _ in residents:
                if self.rng.random() < 0.75:
                    PollVote.objects.create(poll=poll, option=self.rng.choice(opts), user=user, unit=unit)

        # Events ------------------------------------------------------------------------------------
        for title, desc, days, venue, cat, cap in [
            ('Diwali Milan', 'Rangoli competition, diya painting for kids, music and community dinner.', 8,
             'Clubhouse Lawn', 'Festival', 300),
            ('Sunday Yoga & Pranayama', 'Free weekly session with a certified instructor. Bring your own mat.', 3,
             'Terrace Garden', 'Fitness', 40),
            ('Inter-tower Box Cricket', 'Tower-wise teams, 6 overs a side. Register with the society office.', 15,
             'Sports Court', 'Sports', 120),
            ('Blood Donation Camp', 'In association with a local blood bank. Refreshments for all donors.', 22,
             'Clubhouse Hall', 'Community', 80),
        ]:
            e = Event.objects.create(community=c, title=title, description=desc, venue=venue, category=cat, capacity=cap,
                                     starts_at=self.at(days=days, hours=10 - self.now.hour), created_by=manager)
            for user, unit, _ in residents:
                if self.rng.random() < 0.5:
                    EventRSVP.objects.create(event=e, user=user, unit=unit, guests=self.rng.randint(0, 3))

        # Help desk tickets -------------------------------------------------------------------------
        cats = {t.name: t for t in TicketCategory.objects.filter(community=None)}
        issues = [
            ('Plumbing', 'Bathroom tap leaking continuously', 'Water dripping from the wash-basin tap since yesterday.', 'medium', 'open'),
            ('Electrical', 'Corridor light not working on our floor', 'Two tube lights near the lift are off.', 'low', 'in_progress'),
            ('Lift', 'Lift stuck between floors', 'Lift stopped for 5 minutes this morning. Please get it checked.', 'urgent', 'in_progress'),
            ('Housekeeping', 'Garbage not collected', 'Dry waste not picked up for two days.', 'medium', 'resolved'),
            ('Parking', 'Unknown car in my parking slot', 'A white car is parked in my allotted slot since last night.', 'high', 'open'),
            ('Plumbing', 'Low water pressure in kitchen', 'Very low pressure in the kitchen tap after 7 AM.', 'medium', 'on_hold'),
        ]
        assignee = {'Plumbing': facility['Plumber'], 'Electrical': facility['Electrician'], 'Lift': facility['Lift Technician'],
                    'Housekeeping': facility['Housekeeping Supervisor']}
        for i, (cat, title, desc, prio, status) in enumerate(issues):
            user, unit, _ = residents[(i * 3) % len(residents)]
            t = Ticket.objects.create(community=c, unit=unit, raised_by=user, category=cats.get(cat) or next(iter(cats.values())),
                                      number=next_ticket_number(c), title=title, description=desc, priority=prio,
                                      status=status, assigned_to=assignee.get(cat) if status != 'open' else None,
                                      resolved_at=self.at(days=-1) if status == 'resolved' else None)
            Ticket.objects.filter(pk=t.pk).update(created_at=self.at(days=-(i + 1), hours=-i))
            TicketUpdate.objects.create(ticket=t, author=user, message='Ticket raised', status_change='open')
            if status != 'open':
                TicketUpdate.objects.create(ticket=t, author=manager, message=f'Assigned to {assignee.get(cat).name if assignee.get(cat) else "facility team"}',
                                            status_change=status)
            if status == 'resolved':
                Ticket.objects.filter(pk=t.pk).update(rating=5, rating_comment='Quick response, thank you!')

        # Visitors ----------------------------------------------------------------------------------
        for i, (name, vtype, company, status, offset_h) in enumerate([
            ('Swiggy delivery', 'delivery', 'Swiggy', 'exited', -26), ('Zomato delivery', 'delivery', 'Zomato', 'exited', -20),
            ('Amazon delivery', 'delivery', 'Amazon', 'exited', -5), ('Blinkit delivery', 'delivery', 'Blinkit', 'inside', -0.2),
            ('Ola cab', 'cab', 'Ola', 'exited', -30), ('Uber cab', 'cab', 'Uber', 'expected', 2),
            ('Rajesh (cousin)', 'guest', '', 'expected', 5), ('Carpenter – furniture repair', 'service', 'Sai Furniture', 'inside', -1),
            ('Courier – Blue Dart', 'delivery', 'Blue Dart', 'waiting', 0), ('Neighbours from Kothrud', 'guest', '', 'exited', -50),
        ]):
            user, unit, _ = residents[i % len(residents)]
            when = self.at(hours=offset_h)
            kw = dict(community=c, unit=unit, name=name, visitor_type=vtype, company=company, status=status, gate=gate,
                      phone=f'{PHONE_PREFIX}{self.rng.randint(0, 99999):05d}' if vtype == 'guest' else '',
                      pass_code=new_pass_code(c) if status == 'expected' else '', created_by=user if status == 'expected' else guards[0],
                      is_walk_in=status in ('waiting', 'inside') and vtype == 'delivery')
            if vtype == 'cab':
                kw['vehicle_no'] = f'MH 12 {self.rng.choice("ABCDEFGHJK")}{self.rng.choice("ABCDEFGHJK")} {self.rng.randint(1000, 9999)}'
            if status == 'expected':
                kw.update(expected_at=when, valid_until=when + timedelta(hours=8))
            elif status in ('inside', 'exited'):
                kw['checked_in_at'] = when
                if status == 'exited':
                    kw['checked_out_at'] = when + timedelta(minutes=self.rng.randint(5, 180))
            Visitor.objects.create(**kw)

        # Daily help --------------------------------------------------------------------------------
        for name, role, timing in [('Sunita Gaikwad', 'Maid', '7:00 AM – 10:00 AM'), ('Laxmi Pawar', 'Cook', '11:00 AM – 1:00 PM'),
                                   ('Raju Kamble', 'Driver', '8:00 AM – 8:00 PM'), ('Kamala Devi', 'Nanny', '9:00 AM – 6:00 PM')]:
            h = DailyHelp.objects.create(community=c, name=name, role=role, phone=f'{PHONE_PREFIX}{self.rng.randint(0, 99999):05d}',
                                         id_verified=True, pass_code=new_pass_code(c))
            for user, unit, _ in self.rng.sample(residents, min(2, len(residents))):
                DailyHelpAssignment.objects.create(helper=h, unit=unit, timing=timing, added_by=user)
            for d in range(1, 6):
                day = today - timedelta(days=d)
                start = timezone.make_aware(timezone.datetime(day.year, day.month, day.day, 7, 0))
                DailyHelpAttendance.objects.create(helper=h, date=day, gate=gate, check_in=start, check_out=start + timedelta(hours=3))

        # Vendors, forum, classifieds -----------------------------------------------------------------
        for name, cat, price, eta, phone in [('Shree Ganesh Plumbing', 'Plumber', 299, 'Within 2 hours', '9822000001'),
                                             ('Sai Electricals', 'Electrician', 249, 'Same day', '9822000002'),
                                             ('CleanHome Deep Cleaning', 'Cleaning', 1499, 'Next day', '9822000003'),
                                             ('CoolAir AC Service', 'AC Repair', 499, 'Within 4 hours', '9822000004'),
                                             ('Fresh Mart Groceries', 'Grocery', 0, '30 minutes', '9822000005'),
                                             ('Annapurna Tiffin Service', 'Tiffin', 120, 'Lunch & dinner', '9822000006')]:
            ServiceVendor.objects.create(community=c, name=name, category=cat, price_from=price, eta_text=eta,
                                         phone=f'+91{phone}', currency=cur, description=f'{cat} services for residents.')
        a, b, d = residents[0], residents[min(1, len(residents) - 1)], residents[-1]
        post = ForumPost.objects.create(community=c, unit=a[1], author=a[0], tag='Recommendations',
                                        title='Good maid or cook recommendations?',
                                        body='Looking for a reliable cook for evening meals (Maharashtrian food). Any suggestions?')
        ForumReply.objects.create(post=post, author=b[0], body='Laxmi tai cooks for us, very good. Check Daily help in the app.')
        ForumPost.objects.create(community=c, unit=b[1], author=b[0], tag='Carpool', title='Carpool to Hinjewadi Phase 1',
                                 body='Leaving at 8:15 AM on weekdays, two seats available. Sharing fuel cost.')
        ForumPost.objects.create(community=c, unit=d[1], author=d[0], tag='Lost & found', title='Found a kid\'s bicycle near Gate 1',
                                 body='Blue Hero bicycle near the main gate since Sunday. Kept with security.')
        for (user, unit, _), (title, price, cat) in zip(residents, [('Godrej double-door fridge (3 yrs old)', 12000, 'Appliances'),
                                                                     ('Study table with chair', 3500, 'Furniture'),
                                                                     ('Kids cycle 20 inch', 2500, 'Kids'),
                                                                     ('Treadmill – barely used', 18000, 'Fitness')]):
            Classified.objects.create(community=c, unit=unit, seller=user, title=title, price=price, currency=cur,
                                      category=cat, description=f'{title}. Pickup from {unit.label}.')

        # Move-in request & an incident -----------------------------------------------------------------
        mover = residents[-1]
        MoveRequest.objects.create(unit=mover[1], user=mover[0], move_type='move_in', move_date=today + timedelta(days=7),
                                   moving_company='Agarwal Packers & Movers', service_lift=True,
                                   notes='Shifting on Sunday morning, 2 trucks.')
        Incident.objects.create(community=c, reported_by=guards[1], title='Unknown person loitering near parking',
                                description='Person without visitor pass seen near basement parking at 11:30 PM. Asked to leave.',
                                category='Security', severity='medium', location='Basement parking P1', status='investigating')

    # ------------------------------------------------------------------ remove

    def remove(self, communities):
        """Delete only sample records: those made by / for the +9190000 sample people, plus the named sample items."""
        users = User.objects.filter(phone__startswith=PHONE_PREFIX)
        with transaction.atomic():
            for c in communities:
                Ticket.objects.filter(community=c, raised_by__in=users).delete()
                Payment.objects.filter(community=c, user__in=users).delete()
                Invoice.objects.filter(community=c, unit__memberships__user__in=users).distinct().delete()
                Notice.objects.filter(community=c, posted_by__in=users).delete()
                Poll.objects.filter(community=c, created_by__in=users).delete()
                Event.objects.filter(community=c, created_by__in=users).delete()
                Visitor.objects.filter(community=c, created_by__in=users).delete()
                Incident.objects.filter(community=c, reported_by__in=users).delete()
                DailyHelp.objects.filter(community=c, phone__startswith=PHONE_PREFIX).delete()
                ServiceVendor.objects.filter(community=c, phone__startswith='+9198220000').delete()
                StaffMember.objects.filter(community=c, phone__startswith=PHONE_PREFIX).delete()
                EmergencyContact.objects.filter(community=c, group='community', name__in=[
                    'Police', 'Ambulance', 'Fire Brigade', 'Society Office', 'Security Cabin (Main Gate)']).delete()
                ChargeType.objects.filter(community=c, invoice__isnull=True, name__in=[
                    'Monthly maintenance', 'Water charges', 'Parking (extra slot)', 'Clubhouse booking']).delete()
                c.settings = {k: v for k, v in (c.settings or {}).items() if k != MARK}
                c.save(update_fields=['settings'])
            if not Community.objects.filter(**{f'settings__{MARK}': True}).exists():
                users.delete()  # memberships, families, vehicles, votes, RSVPs, posts... go with them
        self.stdout.write(self.style.SUCCESS('Removed the sample data. Your own records were kept.'))
