# Alphabet — Customer App

Flutter app for customers. Requires the FastAPI backend running.

## Setup

```bash
cd apps/customer_app
flutter pub get
```

## Run

```bash
# Android emulator
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# iOS simulator
flutter run --dart-define=API_BASE_URL=http://localhost:8000

# Physical device (replace with your machine's local IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.x:8000
```

## Build for release

```bash
# Android
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.yourdomain.com \
  --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY

# iOS
flutter build ios --release \
  --dart-define=API_BASE_URL=https://api.yourdomain.com \
  --dart-define=GOOGLE_MAPS_API_KEY=YOUR_KEY
```

## Screen map

| Route              | Screen                        |
|--------------------|-------------------------------|
| `/`                | Splash (session check)        |
| `/auth/phone`      | Phone number entry            |
| `/auth/otp`        | OTP verification              |
| `/home`            | Merchant listing + categories |
| `/merchant`        | Menu browsing + add to cart   |
| `/cart`            | Cart review                   |
| `/checkout`        | Address + payment method      |
| `/mpesa-payment`   | M-Pesa STK Push + polling     |
| `/tracking`        | Live map + order status       |
| `/orders`          | Order history                 |
| `/rate-order`      | Post-delivery rating          |
| `/profile`         | Profile + logout              |

## Security features

- JWT stored in `flutter_secure_storage` (Keychain / EncryptedSharedPreferences)
- Biometric unlock on return sessions
- Certificate pinning via Dio interceptor
- Screenshot blocked on checkout and payment screens (`FLAG_SECURE`)
- Root/jailbreak detection on startup
