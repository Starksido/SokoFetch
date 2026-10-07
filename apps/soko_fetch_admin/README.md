# Soko Fetch admin panel

Web app for admins to approve or reject new shops and riders. It is separate
from the customer/merchant/courier app on purpose: admin accounts can't sign
in to that app, and its tokens don't work here (or the other way round).

Admins sign in with their phone number and an SMS code (`/admin/auth/*`).
Admin accounts are created on the server:

```sh
cd backend
poetry run python -m scripts.create_admin --phone 07XXXXXXXX
```

The login is kept in the browser tab's sessionStorage, so closing the tab logs
the admin out.

## Run

```sh
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000
```

## Build and host

```sh
flutter build web --dart-define=API_BASE_URL=https://api.example.com
```

`build/web` is a static site. In production, set `ADMIN_PANEL_ORIGIN` in the
backend's `.env` to the address it is served from, so the API allows it (CORS).
Serve it somewhere only admins can reach if possible.

## Checks

```sh
flutter analyze
flutter test
flutter build web
```
