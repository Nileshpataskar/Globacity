# GlobaCity Guard

Security-desk app for guards (and admins/managers who run the gate). It is a thin shell: all screens and logic come
from the main GlobaCity package one folder up (`../lib`, started via `runGuardApp()`).

```bash
cd guard_app
flutter run --dart-define=API_URL=https://globacity-api.onrender.com            # emulator / phone
flutter build apk --release --split-per-abi --dart-define=API_URL=https://globacity-api.onrender.com
```

Guards sign in with the phone number an admin added under **Staff & roles** (role: Guard).
Icon: `assets/icon/` → `dart run flutter_launcher_icons`.
