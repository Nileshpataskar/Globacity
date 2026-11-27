# GlobaCity

GlobaCity is an app for gated communities and apartment societies. Residents, security guards and the
management office all use the same system:

- **Residents** approve visitors, pay maintenance, raise complaints and follow what's happening in the society.
- **Guards** check visitors in and out at the gate.
- **Managers** set up towers and flats and run everything from a web dashboard.

It works in any country. Currency, phone code, timezone and tax come from each community's settings.

## Links

| What | Link |
|---|---|
| Admin dashboard (web) | https://globacity-admin.vercel.app |
| API | https://globacity-api.onrender.com |
| API docs (Swagger) | https://globacity-api.onrender.com/api/docs/ |
| Android apps (APK) | [Releases](https://github.com/Nileshpataskar/Globacity/releases/latest): `GlobaCity.apk` and `GlobaCity-Guard.apk` |

The server is on a free plan and sleeps after 15 minutes without traffic. The first request after that takes
about a minute.

## The three apps

### 1. GlobaCity (residents' phone app)
- **Gate:** when a visitor arrives, your phone rings like a call. You can allow them, decline them, or ask the guard to leave a delivery at the gate.
- **Visitors:** pre-approve guests with a QR pass and see who is inside or expected.
- **Payments:** see maintenance bills and pay them.
- **Help desk:** raise a complaint with a photo and track it until it's fixed.
- **Community:** notices, events with RSVP, polls, facility booking and the residents' directory.
- **Household:** add family members, staff (maid, driver) and vehicles.
- **Multiple flats:** if you have flats in more than one community, switch between them.

### 2. GlobaCity Guard (guards' phone app)
- Scan a visitor's QR pass, or type in their details for a walk-in.
- Ask the resident for approval; they get a call-style alert on their phone.
- Check visitors in and out, and see who is inside right now.
- Start and end a duty shift, with a shift log.

### 3. Admin dashboard (web)
- Create communities, towers and gates.
- **Quick add flats:** for example "3 floors × 4 flats", with a building-plan preview before anything is created.
- Approve new residents, and manage guards, shifts, bills, notices, events, polls and complaints.
- **Tower admins** see and manage only their own tower.

## How to use

**Resident**
1. Install `GlobaCity.apk`. On the phone, allow "Install unknown apps" when asked.
2. Open the app and tap **Sign up**. Enter your phone number and the OTP code.
3. Pick your community, tower and flat. The management office approves your request.
4. When Android asks, **allow notifications**, so the phone can ring when a visitor is at the gate.

**Guard**
1. Install `GlobaCity-Guard.apk`.
2. Ask the manager to add your phone number as a guard in the admin dashboard (Guards page).
3. Log in with the OTP code, start your shift, then scan QR passes or add walk-ins.

**Manager**
1. Open the admin dashboard and log in.
2. Add the community, then its towers. Use **Quick add flats** to create the flats.
3. Add guards and approve residents as they sign up.

> No SMS provider is connected yet, so the OTP code is shown inside the app. Use test data only.

### Sample logins (from `seed_india`)

| Role | Phone |
|---|---|
| Resident (B Wing · B-402) | +91 90000 49515 |
| Guard | +91 90000 74470 |

## Run it on your computer

You need [Docker](https://www.docker.com/), [Flutter](https://docs.flutter.dev/get-started/install) and
[Node.js](https://nodejs.org/) 18 or newer.

**1. Backend (API and database)**
```bash
cd backend
cp .env.example .env                                     # first time only
docker compose up -d --build                             # API on http://localhost:8000
docker compose exec web python manage.py bootstrap       # first time: creates the admin login
docker compose exec web python manage.py seed_india      # optional: Indian sample data
```

**2. Admin dashboard**
```bash
cd admin
npm install
npm run dev                                              # http://localhost:5173
```

**3. Phone apps**

On an emulator:
```bash
flutter run --dart-define=API_URL=http://10.0.2.2:8000                    # resident app
cd guard_app && flutter run --dart-define=API_URL=http://10.0.2.2:8000    # guard app
```

On a real phone over USB, first run `adb reverse tcp:8000 tcp:8000`, then use `API_URL=http://localhost:8000`.

**Build the APKs** (pointing at the live server):
```bash
flutter build apk --release --split-per-abi --dart-define=API_URL=https://globacity-api.onrender.com
cd guard_app && flutter build apk --release --split-per-abi --dart-define=API_URL=https://globacity-api.onrender.com
```
The APK to share is `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. It runs on almost every modern Android phone.

## Project layout

```
lib/          Resident app (Flutter)
guard_app/    Guard app (Flutter; reuses code from lib/)
admin/        Admin dashboard (React + Vite)
backend/      API (Django REST + Channels for live alerts, PostgreSQL)
render.yaml   Hosting setup for Render
```

Hosting is free: the API runs on Render, the database on Neon and the dashboard on Vercel. See
[DEPLOY.md](DEPLOY.md) for setup.

## Known limits
- The visitor call-alert rings only while the resident app is open or in the background. Ringing when the app is fully closed needs Firebase Cloud Messaging, which isn't added yet.
- OTP codes are shown in the app instead of sent by SMS.
- Photos uploaded to the free server are wiped when it redeploys.
