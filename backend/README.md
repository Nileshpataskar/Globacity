# Globacity API

Django REST backend for the Globacity community app. Everything is free and open source:
PostgreSQL, Redis, Django, DRF, Swagger (drf-spectacular). OTP codes print to the console and payments use a mock gateway.

## Run

```bash
cd backend
cp .env.example .env              # first time only
docker compose up -d --build      # PostgreSQL + Redis + API on :8000 + admin dashboard on :8080
docker compose exec web python manage.py seed_demo   # demo data (first time only)
```

| URL | What |
|---|---|
| http://localhost:8080/ | **Admin web dashboard** (React app in `../admin`; log in as an admin, tower admin or manager). After changes run `npm run build` in `admin/`, then reload |
| http://localhost:8000/api/docs/ | Swagger UI (try every endpoint) |
| http://localhost:8000/api/redoc/ | ReDoc |
| http://localhost:8000/admin/ | Django admin for the platform admin |
| ws://localhost:8000/ws/notifications/?token=ACCESS | Live notifications |

Other commands:

```bash
docker compose logs -f web                              # API logs (OTP codes appear here)
docker compose exec web python manage.py test           # end-to-end API tests
docker compose exec web python manage.py makemigrations # after model changes
docker compose down                                     # stop (data is kept in the pgdata volume)
```

## Demo logins (after `seed_demo`)

| Role | Phone | Password |
|---|---|---|
| Platform admin | +971500000001 | Admin@12345 |
| Community admin, Palm Vista (Dubai, AED) | +971500000002 | Manager@12345 |
| Community admin, Sea Breeze (Mumbai, INR) | +919800000002 | Manager@12345 |
| Guard, Palm Vista | +971500000003 | Guard@12345 |
| Resident with one unit in Dubai and one in Mumbai | +971501234567 | OTP only |

**Swagger login:** `POST /api/v1/auth/otp/request/` returns `debug_code` while `DEBUG=true`. Send it to
`POST /api/v1/auth/otp/verify/`, then click **Authorize** and paste the `access` token. Staff accounts can also
use `POST /api/v1/auth/login/`.

## How it is organised

```
Country (currency, phone code, timezone, languages, tax, payment gateway, emergency numbers)
 └─ City
     └─ Community (branding, settings)
         ├─ Tower ─ Unit ─ Membership (owner / tenant / family, needs approval)
         ├─ Gate
         └─ StaffMember (admin / manager / guard / committee / facility)
```

**Nothing is hard-coded to one country.** Each community inherits its locale from its country. Invoices and
payments store their own currency and tax rate when they are created. Amounts are rounded to the currency's
decimal places (e.g. KWD uses 3). `GET /api/v1/context/` returns the selected unit's country, currency, tax,
timezone, languages and branding, and the app renders from it.

### API areas

| Prefix | Who | Examples |
|---|---|---|
| `/auth/`, `/me/`, `/countries/` | Everyone | OTP login, JWT refresh, profile, settings, my units |
| `/platform/` | Platform admin (`is_staff`) | currencies, countries, cities, communities |
| `/manage/` | Community admin/manager | towers (+ bulk unit generation), units, gates, memberships, staff, notices, polls, events, invoices (+ bulk), payments, defaulters (+ reminders), tickets, vendors, move requests, moderation |
| `/guard/` | Guards | verify / check-in by code, walk-in approval requests, check-out, daily help, kid exits, SOS |
| everything else | Residents | context, visitors, frequent entries, household, daily help (attendance, reviews), finance, notices, polls, events, forum, classifieds, services, move requests, help desk, SOS, kid exit, emergency contacts, directory, chat, notifications, search |

Resident endpoints act on one unit. Send the `X-Unit-ID` header with a unit id from `GET /me/units/`. You can
leave it out if the user belongs to exactly one unit.

### First-time setup of a real community

1. Platform admin: `POST /platform/countries/` (if missing) → `POST /platform/cities/` → `POST /platform/communities/`
2. Platform admin: `POST /manage/staff/` with `role=admin` and `user_phone` to create the community admin
3. Community admin: `POST /manage/towers/` → `POST /manage/towers/{id}/generate-units/` → `POST /manage/gates/`
4. Residents sign up with OTP → `POST /me/units/` (join request) → admin approves with `POST /manage/memberships/{id}/approve/`

## Plugging in paid providers later

| What | Where | Default (free) |
|---|---|---|
| SMS / OTP | `apps/accounts/sms.py` + `SMS_BACKEND` in `.env` | console log |
| Email | `EMAIL_BACKEND` in `.env` | console log |
| Payments | `apps/finance/gateways.py`; choose per country in the platform admin | `mock` (confirm via `/finance/payments/{id}/mock-confirm/`) |
| Push | `notifications.Device` tokens are stored; add FCM sending in `apps/notifications/service.py` | WebSocket + in-app list |
