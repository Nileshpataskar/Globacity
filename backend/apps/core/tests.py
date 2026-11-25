"""End-to-end API flows across roles and countries. Run: docker compose run --rm web python manage.py test"""

from datetime import timedelta
from decimal import Decimal

from django.core.cache import cache
from django.core.management import call_command
from django.test import override_settings
from django.utils import timezone
from rest_framework.test import APITestCase

from apps.accounts.models import User
from apps.communities.models import Community, Membership, Unit
from apps.finance.models import Invoice
from apps.household.models import DailyHelp
from apps.notifications.models import Notification

API = '/api/v1'
RESIDENT = '+971501234567'


@override_settings(DEBUG=True)  # OTP code is returned in the response only in DEBUG
class Base(APITestCase):
    @classmethod
    def setUpTestData(cls):
        call_command('seed_demo', verbosity=0, stdout=open('/dev/null', 'w'))
        cls.palm = Community.objects.get(slug='palm-vista-residences')
        cls.sea = Community.objects.get(slug='sea-breeze-towers')
        cls.dubai_unit = Unit.objects.get(tower__community=cls.palm, tower__name='Tower B', number='1204')
        cls.mumbai_unit = Unit.objects.get(tower__community=cls.sea, tower__name='Tower 1', number='803')

    def setUp(self):
        cache.clear()

    # helpers -----------------------------------------------------------------

    def login_otp(self, phone, **extra):
        r = self.client.post(f'{API}/auth/otp/request/', {'phone': phone}, format='json')
        self.assertEqual(r.status_code, 200, r.data)
        r = self.client.post(f'{API}/auth/otp/verify/', {'phone': phone, 'code': r.data['debug_code'], **extra},
                             format='json')
        self.assertEqual(r.status_code, 200, r.data)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {r.data["access"]}')
        return r.data

    def login_password(self, phone, password):
        r = self.client.post(f'{API}/auth/login/', {'identifier': phone, 'password': password}, format='json')
        self.assertEqual(r.status_code, 200, r.data)
        self.client.credentials(HTTP_AUTHORIZATION=f'Bearer {r.data["access"]}')

    def as_resident(self, unit=None):
        self.login_otp(RESIDENT)
        if unit is not None:
            self.client.credentials(HTTP_AUTHORIZATION=self.client._credentials['HTTP_AUTHORIZATION'],
                                    HTTP_X_UNIT_ID=str(unit.pk))

    def get(self, path, expect=200, **params):
        r = self.client.get(f'{API}{path}', params)
        self.assertEqual(r.status_code, expect, getattr(r, 'data', r))
        return r.data

    def post(self, path, data=None, expect=200):
        r = self.client.post(f'{API}{path}', data or {}, format='json')
        self.assertEqual(r.status_code, expect, getattr(r, 'data', r))
        return r.data

    def patch(self, path, data, expect=200):
        r = self.client.patch(f'{API}{path}', data, format='json')
        self.assertEqual(r.status_code, expect, getattr(r, 'data', r))
        return r.data


class Flows(Base):
    # auth & docs -------------------------------------------------------------

    def test_docs_and_public_countries(self):
        self.assertEqual(self.client.get('/api/docs/').status_code, 200)
        self.assertEqual(self.client.get('/api/schema/').status_code, 200)
        countries = {c['iso2']: c for c in self.get('/countries/')}
        self.assertEqual(countries['AE']['currency']['code'], 'AED')
        self.assertEqual(countries['IN']['phone_code'], '+91')

    def test_signup_then_set_email_and_password(self):
        data = self.login_otp('+971508887766', full_name='Signup User')
        self.assertFalse(data['user']['has_password'])
        self.patch('/me/', {'email': 'signup.user@example.com'})
        self.post('/me/password/', {'new_password': 'Signup@12345'})
        self.client.credentials()
        r = self.client.post(f'{API}/auth/login/', {'identifier': 'signup.user@example.com', 'password': 'Signup@12345'},
                             format='json')
        self.assertEqual(r.status_code, 200, r.data)

    def test_otp_signup_and_phone_validation(self):
        data = self.login_otp('+971509876543', full_name='New Person')
        self.assertTrue(data['is_new_user'])
        self.assertEqual(data['user']['full_name'], 'New Person')
        self.client.credentials()
        r = self.client.post(f'{API}/auth/otp/request/', {'phone': '+15551234567'}, format='json')
        self.assertEqual(r.status_code, 400)  # country not supported
        r = self.client.post(f'{API}/auth/otp/request/', {'phone': '+9715012'}, format='json')
        self.assertEqual(r.status_code, 400)  # wrong length for UAE
        r = self.client.post(f'{API}/auth/otp/verify/', {'phone': RESIDENT, 'code': '000000'}, format='json')
        self.assertEqual(r.status_code, 400)

    # country independence ----------------------------------------------------

    def test_context_follows_selected_unit_country(self):
        self.login_otp(RESIDENT)
        self.assertEqual(len(self.get('/me/units/')), 2)
        self.get('/context/', expect=400)  # two units -> header required
        self.as_resident(self.dubai_unit)
        ctx = self.get('/context/')
        self.assertEqual(ctx['country']['currency']['code'], 'AED')
        self.assertEqual(ctx['country']['tax_name'], 'VAT')
        self.assertEqual(ctx['community']['timezone'], 'Asia/Dubai')
        self.as_resident(self.mumbai_unit)
        ctx = self.get('/context/')
        self.assertEqual(ctx['country']['currency']['code'], 'INR')
        self.assertEqual(ctx['country']['tax_name'], 'GST')
        self.assertEqual(ctx['community']['timezone'], 'Asia/Kolkata')

    def test_invoices_use_country_currency_and_tax(self):
        self.as_resident(self.dubai_unit)
        dues = self.get('/finance/invoices/', open='true')['results']
        service = next(d for d in dues if d['title'] == 'Service charges')
        self.assertEqual(service['currency'], 'AED')
        self.assertEqual(Decimal(service['total']), Decimal('2572.50'))  # 2450 + 5% VAT
        self.as_resident(self.mumbai_unit)
        dues = self.get('/finance/invoices/', open='true')['results']
        service = next(d for d in dues if d['title'] == 'Service charges')
        self.assertEqual(service['currency'], 'INR')
        self.assertEqual(Decimal(service['total']), Decimal('21830.00'))  # 18500 + 18% GST

    def test_checkout_mock_gateway_and_statement(self):
        self.as_resident(self.dubai_unit)
        summary = self.get('/finance/invoices/summary/')
        self.assertGreater(Decimal(summary['outstanding']), 0)
        ids = [d['id'] for d in self.get('/finance/invoices/', open='true')['results']]
        res = self.post('/finance/payments/checkout/', {'invoice_ids': ids, 'method': 'card'}, expect=201)
        self.assertEqual(res['checkout']['gateway'], 'mock')
        self.assertEqual(Decimal(res['payment']['amount']), Decimal(summary['outstanding']))
        with self.captureOnCommitCallbacks(execute=True):
            paid = self.post(f'/finance/payments/{res["payment"]["id"]}/mock-confirm/', {'success': True})
        self.assertEqual(paid['status'], 'success')
        self.assertEqual(Decimal(self.get('/finance/invoices/summary/')['outstanding']), 0)
        self.assertEqual(Decimal(self.get('/finance/invoices/statement/')['closing_balance']), 0)
        self.assertTrue(Notification.objects.filter(title='Payment received').exists())
        # Paying the Mumbai unit's invoices with the Dubai unit selected must fail.
        mumbai_ids = [str(i.pk) for i in Invoice.objects.filter(unit=self.mumbai_unit, status='unpaid')]
        self.post('/finance/payments/checkout/', {'invoice_ids': mumbai_ids, 'method': 'card'}, expect=400)

    # gate ----------------------------------------------------------------------

    def test_preapproved_visitor_guard_check_in_and_out(self):
        self.as_resident(self.dubai_unit)
        v = self.post('/visitors/', {'name': 'Test Guest', 'visitor_type': 'guest', 'guests': 2}, expect=201)
        self.assertEqual(len(v['pass_code']), 6)
        self.login_password('+971500000003', 'Guard@12345')
        found = self.post('/guard/visitors/verify/', {'code': v['pass_code']})
        self.assertEqual((found['kind'], found['allowed']), ('visitor', True))
        self.post('/guard/visitors/check-in/', {'code': v['pass_code']})
        self.assertTrue(Notification.objects.filter(title='Test Guest has arrived').exists())
        self.assertEqual(self.post(f'/guard/visitors/{v["id"]}/check-out/')['status'], 'exited')
        self.post('/guard/visitors/verify/', {'code': v['pass_code']}, expect=404)  # pass used up

    def test_walk_in_approval_and_guard_isolation(self):
        self.login_password('+971500000003', 'Guard@12345')
        v = self.post('/guard/visitors/walk-in/', {'unit': str(self.dubai_unit.pk), 'name': 'Noon Delivery',
                                                   'visitor_type': 'delivery', 'company': 'Noon'}, expect=201)
        self.assertEqual(v['status'], 'waiting')
        # A Dubai guard cannot raise requests for a Mumbai unit.
        self.post('/guard/visitors/walk-in/', {'unit': str(self.mumbai_unit.pk), 'name': 'X'}, expect=403)
        self.as_resident(self.dubai_unit)
        self.assertEqual(self.post(f'/visitors/{v["id"]}/approve/')['status'], 'inside')
        self.post(f'/visitors/{v["id"]}/deny/', expect=400)  # no longer waiting

    def test_unit_isolation(self):
        self.as_resident(Unit.objects.get(tower__community=self.palm, tower__name='Tower A', number='101'))
        self.get('/visitors/', expect=403)

    def test_daily_help_attendance_and_gate_code(self):
        self.as_resident(self.dubai_unit)
        helpers = {h['name']: h for h in self.get('/household/daily-help/')['results']}
        self.assertTrue(helpers['Fatima Noor']['is_inside'])
        self.assertEqual(helpers['Fatima Noor']['homes_served'], 2)
        att = self.get(f'/household/daily-help/{helpers["Ramesh Kumar"]["id"]}/attendance/')
        self.assertGreater(att['days_present'], 0)
        self.post(f'/household/daily-help/{helpers["Maria Santos"]["id"]}/reviews/', {'rating': 4}, expect=201)
        self.login_password('+971500000003', 'Guard@12345')
        self.post('/guard/visitors/check-in/', {'code': helpers['Fatima Noor']['pass_code']}, expect=400)  # inside
        DailyHelp.objects.get(name='Ramesh Kumar').attendance.update(check_out=timezone.now())
        self.post('/guard/visitors/check-in/', {'code': helpers['Ramesh Kumar']['pass_code']})
        self.assertTrue(Notification.objects.filter(title='Ramesh Kumar checked in').exists())

    def test_sos_and_kid_exit(self):
        self.as_resident(self.dubai_unit)
        sos = self.post('/sos/', {'alert_type': 'medical', 'message': 'Help'}, expect=201)
        kid = Membership.objects.get(user__phone=RESIDENT, unit=self.dubai_unit).unit.family_members.filter(
            is_minor=True).first()
        self.post('/kid-exits/', {'children': [str(kid.pk)], 'duration_minutes': 60}, expect=201)
        contacts = self.get('/emergency-contacts/')
        self.assertIn('999', [c['phone'] for c in contacts])  # UAE police from country config
        self.login_password('+971500000003', 'Guard@12345')
        self.assertEqual(len(self.get('/guard/kid-exits/')['results']), 1)
        self.assertEqual(self.post(f'/guard/sos/{sos["id"]}/acknowledge/')['status'], 'acknowledged')

    # management & platform ------------------------------------------------------

    def test_manager_flows(self):
        self.login_password('+971500000002', 'Manager@12345')
        pending = self.get('/manage/memberships/', status='pending')['results']
        self.assertEqual(len(pending), 1)
        self.assertEqual(self.post(f'/manage/memberships/{pending[0]["id"]}/approve/')['status'], 'approved')
        tower = self.post('/manage/towers/', {'community': str(self.palm.pk), 'name': 'Tower D', 'floors': 0},
                          expect=201)
        gen = self.post(f'/manage/towers/{tower["id"]}/generate-units/',
                        {'floor_from': 1, 'floor_to': 3, 'units_per_floor': 2})
        self.assertEqual(gen['created'], 6)
        res = self.post('/manage/invoices/bulk/', {'community': str(self.palm.pk), 'title': 'Pool fee',
                                                   'amount': '100', 'due_date': str(timezone.localdate()),
                                                   'taxable': True})
        self.assertEqual(res['created'], Unit.objects.filter(tower__community=self.palm,
                                                             memberships__status='approved').distinct().count())
        self.assertEqual(Invoice.objects.filter(title='Pool fee').first().total, Decimal('105.000'))
        defaulters = self.get('/manage/defaulters/', community=str(self.palm.pk))
        self.assertTrue(any(d['unit'] == str(self.dubai_unit.pk) for d in defaulters))
        self.assertGreaterEqual(self.post('/manage/defaulters/remind/', {'community': str(self.palm.pk)})[
            'units_notified'], 1)
        # A Dubai admin cannot manage the Mumbai community.
        self.post('/manage/towers/', {'community': str(self.sea.pk), 'name': 'Hack'}, expect=403)
        self.assertEqual(self.get('/manage/towers/', community=str(self.sea.pk))['count'], 0)

    def test_platform_admin_registers_country_to_community(self):
        self.login_password('+971500000002', 'Manager@12345')
        self.post('/platform/countries/', {}, expect=403)
        self.login_password('+971500000001', 'Admin@12345')
        country = self.post('/platform/countries/', {
            'name': 'Kuwait', 'iso2': 'KW', 'phone_code': '+965', 'phone_number_length': 8, 'currency': 'KWD',
            'timezone': 'Asia/Kuwait', 'tax_name': 'VAT', 'tax_rate': '0', 'supported_languages': ['ar', 'en'],
            'emergency_numbers': {'emergency': '112'}}, expect=201)
        city = self.post('/platform/cities/', {'country': country['id'], 'name': 'Kuwait City'}, expect=201)
        community = self.post('/platform/communities/', {'city': city['id'], 'name': 'Gulf Pearl'}, expect=201)
        self.assertEqual(community['currency'], 'KWD')
        staff = self.post('/manage/staff/', {'community': community['id'], 'name': 'KW Admin', 'role': 'admin',
                                             'user_phone': '+96551234567'}, expect=201)
        self.assertIsNotNone(staff['user'])
        # The new admin can now manage only their community; invoices are in KWD with 3 decimals.
        admin = User.objects.get(phone='+96551234567')
        admin.set_password('Kuwait@12345')
        admin.save()
        self.login_password('+96551234567', 'Kuwait@12345')
        tower = self.post('/manage/towers/', {'community': community['id'], 'name': 'A'}, expect=201)
        unit = self.post('/manage/units/', {'tower': tower['id'], 'number': '101'}, expect=201)
        inv = self.post('/manage/invoices/', {'unit': unit['id'], 'title': 'Service', 'amount': '12.345',
                                              'due_date': str(timezone.localdate())}, expect=201)
        self.assertEqual((inv['currency'], inv['total']), ('KWD', '12.345'))

    # helpdesk, community, messaging ---------------------------------------------

    def test_ticket_lifecycle(self):
        self.as_resident(self.dubai_unit)
        cat = self.get('/helpdesk/categories/')[0]
        t = self.post('/helpdesk/tickets/', {'category': cat['id'], 'title': 'Door lock broken',
                                             'priority': 'high'}, expect=201)
        self.assertEqual(t['number'], 'T-1002')
        self.login_password('+971500000002', 'Manager@12345')
        self.patch(f'/manage/tickets/{t["id"]}/', {'status': 'resolved'})
        self.post(f'/manage/tickets/{t["id"]}/comment/', {'message': 'internal note', 'is_internal': True},
                  expect=201)
        self.as_resident(self.dubai_unit)
        detail = self.get(f'/helpdesk/tickets/{t["id"]}/')
        self.assertEqual(detail['status'], 'resolved')
        self.assertNotIn('internal note', [u['message'] for u in detail['updates']])
        self.assertEqual(self.post(f'/helpdesk/tickets/{t["id"]}/rate/', {'rating': 5})['status'], 'closed')

    def test_community_engagement(self):
        self.as_resident(self.dubai_unit)
        self.assertGreater(self.get('/notices/')['count'], 0)
        poll = next(p for p in self.get('/polls/')['results'] if p['my_vote'] is None)
        voted = self.post(f'/polls/{poll["id"]}/vote/', {'option': poll['options'][0]['id']})
        self.assertEqual(voted['my_vote'], poll['options'][0]['id'])
        self.post(f'/polls/{poll["id"]}/vote/', {'option': poll['options'][0]['id']}, expect=400)
        event = self.get('/events/')['results'][0]
        self.assertTrue(self.post(f'/events/{event["id"]}/rsvp/', {'going': True, 'guests': 2})['going'])
        post = self.post('/forum/posts/', {'title': 'Hello', 'body': 'Hi all'}, expect=201)
        self.post(f'/forum/posts/{post["id"]}/replies/', {'body': 'Welcome'}, expect=201)
        self.assertTrue(self.post(f'/forum/posts/{post["id"]}/like/')['liked'])
        ad = self.post('/classifieds/', {'title': 'Lamp', 'price': '20', 'category': 'Furniture'}, expect=201)
        self.assertEqual(ad['currency'], 'AED')
        self.as_resident(self.mumbai_unit)
        self.assertEqual(self.post('/classifieds/', {'title': 'Fan', 'price': '900'}, expect=201)['currency'], 'INR')
        self.post(f'/classifieds/{ad["id"]}/mark-sold/', expect=404)  # other community
        vendor = self.as_resident(self.dubai_unit) or self.get('/services/vendors/')['results'][0]
        booking = self.post('/services/bookings/', {'vendor': vendor['id'],
                                                    'slot_start': (timezone.now() + timedelta(days=1)).isoformat()},
                            expect=201)
        self.assertEqual(booking['status'], 'requested')
        self.post('/move-requests/', {'move_type': 'move_out', 'move_date': str(timezone.localdate())}, expect=201)

    def test_directory_messaging_search(self):
        self.as_resident(self.dubai_unit)
        meera = next(r for r in self.get('/directory/residents/')['results'] if r['name'] == 'Meera Shah')
        self.assertIsNone(meera['phone'])  # privacy default hides phone
        conv = self.post('/conversations/', {'user_id': str(meera['user_id'])}, expect=201)
        self.post(f'/conversations/{conv["id"]}/messages/', {'body': 'Hi Meera!'}, expect=201)
        self.post('/conversations/', {'user_id': str(meera['user_id'])}, expect=200)  # reused
        results = self.get('/search/', q='Fatima')
        self.assertIn('daily_help', [r['type'] for r in results])
        self.patch('/me/settings/', {'privacy_prefs': {'show_phone': True}})
        self.assertTrue(self.get('/me/settings/')['privacy_prefs']['show_phone'])
        self.assertGreater(self.get('/notifications/unread-count/')['unread'], -1)


@override_settings(DEBUG=True)
class GuardFlows(Base):
    """Guard app endpoints."""

    def setUp(self):
        super().setUp()
        self.login_password('+971500000003', 'Guard@12345')

    def test_context_shift_and_summary(self):
        ctx = self.get('/guard/context/')
        self.assertEqual([c['name'] for c in ctx['communities']], ['Palm Vista Residences'])
        gate = next(g for g in ctx['communities'][0]['gates'] if g['name'] == 'Main Gate')
        shift = self.post('/guard/shifts/start/', {'community': ctx['communities'][0]['id'], 'gate': gate['id'],
                                                   'shift': 'morning'}, expect=201)
        self.assertEqual(self.get('/guard/context/')['shift']['id'], shift['id'])
        summary = self.get('/guard/summary/')
        self.assertGreaterEqual(summary['active_passes'], 1)
        self.assertGreaterEqual(summary['waiting_approval'], 1)
        self.assertEqual(self.post(f'/guard/shifts/{shift["id"]}/end/')['ended_at'] is not None, True)

    def test_vehicle_log_matches_resident_vehicle(self):
        self.assertTrue(self.get('/guard/vehicles/lookup/', number='dubai a 12345')['registered'])
        log = self.post('/guard/vehicles/', {'number': 'DUBAI A-12345', 'direction': 'in'}, expect=201)
        self.assertEqual(log['unit_label'], 'Tower B · 1204')
        visitor = self.post('/guard/vehicles/', {'number': 'X 999', 'direction': 'in'}, expect=201)
        self.assertFalse(visitor['is_resident'])

    def test_staff_attendance(self):
        staff = self.get('/guard/staff/')
        plumber = next(s for s in staff if s['name'] == 'Suresh Pillai')
        self.assertTrue(self.post(f'/guard/staff/{plumber["id"]}/check-in/')['is_inside'])
        self.post(f'/guard/staff/{plumber["id"]}/check-in/', expect=400)
        self.assertFalse(self.post(f'/guard/staff/{plumber["id"]}/check-out/')['is_inside'])

    def test_incident_and_iot_gate(self):
        inc = self.post('/guard/incidents/', {'title': 'Broken light', 'severity': 'low', 'location': 'Parking B2'},
                        expect=201)
        self.assertEqual(self.patch(f'/guard/incidents/{inc["id"]}/', {'status': 'resolved'})['status'], 'resolved')
        gates = self.get('/guard/gates/')
        main = next(g for g in gates if g['iot_enabled'])
        self.assertTrue(self.post(f'/guard/gates/{main["id"]}/open/')['success'])
        other = next(g for g in gates if not g['iot_enabled'])
        self.post(f'/guard/gates/{other["id"]}/open/', expect=400)

    def test_directory_hides_phones_when_not_allowed(self):
        rows = {r['unit_label']: r for r in self.get('/guard/directory/', search='1204')}
        mine = rows['Tower B · 1204']
        self.assertIsNotNone(mine['residents'][0]['phone'])
        self.assertIn('Dubai A 12345', mine['vehicles'])
        self.assertEqual(self.get('/guard/directory/', search='Aarav')[0]['unit_label'], 'Tower B · 1204')

    def test_resident_cannot_use_guard_api(self):
        self.as_resident(self.dubai_unit)
        self.get('/guard/summary/', expect=403)
