# Free hosting: Neon + Render + Vercel

| Part | Host | Result |
|---|---|---|
| PostgreSQL | Neon (free) | `postgresql://…neon.tech/…` |
| Django API | Render (free, Docker) | `https://globacity-api.onrender.com` |
| Admin dashboard (React) | Vercel (free) | `https://<project>.vercel.app` |
| Phone app | APK file you share | Talks to the Render URL |

## 0. Put the code on GitHub (once)

Create an **empty private** repository on github.com (no README), then in the project folder:

```bash
cd ~/projects/globacity
git init
git add .
git commit -m "GlobaCity app, API and admin dashboard"
git branch -M main
git remote add origin https://github.com/<you>/globacity.git
git push -u origin main
```

`.gitignore` keeps `backend/.env`, `backups/`, `node_modules` and build output out of Git.

## 1. Database: Neon

1. Sign up at neon.tech → **New project** (region close to your users, e.g. AWS Asia Pacific / Mumbai or Singapore).
2. **Connection string** → copy the one that starts with `postgresql://` (keep `?sslmode=require`).

**Optional: copy your current local data** (communities, towers, flats, users) to Neon. Do this *before* step 2:

```bash
cd ~/projects/globacity/backend
docker compose exec -T db pg_dump -U globacity --no-owner --no-acl globacity \
  | docker run -i --rm postgres:17 psql "PASTE_NEON_CONNECTION_STRING"
```

## 2. API: Render

1. Sign up at render.com with GitHub → **New → Blueprint** → pick the `globacity` repo. Render reads `render.yaml`.
2. It asks for two values:
   - `DATABASE_URL` = the Neon connection string
   - `ADMIN_PASSWORD` = a strong password for the `admin` login (ignored if you copied local data: then the local password applies)
3. **Apply**. The first build takes ~5 minutes. Check `https://<service>.onrender.com/api/docs/`.

Free plan notes: the service **sleeps after 15 minutes without traffic**; the first request after that takes ~1 minute.
Uploaded photos are stored on the server's disk, which is **wiped on every redeploy/restart** (fine for testing).

## 3. Admin dashboard: Vercel

1. Sign up at vercel.com with GitHub → **Add New → Project** → import the repo.
2. **Root Directory**: `admin`. Framework is detected as Vite.
3. **Environment Variables**: `VITE_API_URL` = `https://<service>.onrender.com/api/v1`
4. **Deploy** → open the `.vercel.app` URL and log in.

## 4. Phone app: build and share the APK

```bash
cd ~/projects/globacity
flutter build apk --release --dart-define=API_URL=https://<service>.onrender.com
open build/app/outputs/flutter-apk/       # app-release.apk
```

Send `app-release.apk` (WhatsApp, Google Drive…). On the phone, allow "Install unknown apps" when asked.
Rebuild and resend the APK whenever the app changes. The API and dashboard redeploy automatically on `git push`.

## Security for a public demo

- `OTP_SHOW_CODE=true` shows the login code in the app because there is no SMS provider yet. **Anyone who knows a
  phone number can log in as that person.** Use test data only; set it to `false` in Render once SMS is set up
  (`apps/accounts/sms.py`).
- Change the `admin` password from the Django admin (`/admin/`) if you copied local data (`admin123`).
