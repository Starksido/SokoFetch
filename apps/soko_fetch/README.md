# Soko Fetch app

One app for customers, merchants and couriers. New users verify a phone
number or Google account, then pick Customer, Merchant or Courier; the
account is created with that role and keeps it. Admins use the separate
admin web panel (`apps/soko_fetch_admin`) and can't sign in here.

## Run

```sh
flutter pub get
flutter run --dart-define=API_BASE_URL=http://<your-machine-ip>:8000
```

Google Maps needs a key: add `GOOGLE_MAPS_API_KEY=...` to
`android/gradle.properties` (or pass `-PGOOGLE_MAPS_API_KEY=...`).

## Layout

- `lib/core/` – config, theme, API client (token refresh), session, shared models
- `lib/features/auth/` – splash, welcome (phone / Google), OTP, role picker
- `lib/features/{customer,merchant,courier}/` – each role's screens and its
  routes under `/customer`, `/merchant`, `/courier`

## Checks

```sh
flutter analyze
flutter test
flutter build apk --debug
```
