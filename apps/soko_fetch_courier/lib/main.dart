import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_theme.dart';
import 'network/api_client.dart';
import 'providers/providers.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/dispatch/home_screen.dart';
import 'screens/documents/documents_screen.dart';
import 'screens/delivery/proof_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const ProviderScope(child: CourierApp()));
}

class CourierApp extends StatelessWidget {
  const CourierApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Soko Fetch Courier',
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light,
    initialRoute: '/',
    onGenerateRoute: (s) {
      switch (s.name) {
        case '/':             return _r(const _SplashGate(), s);
        case '/auth/phone':   return _r(const PhoneScreen(), s);
        case '/auth/otp':     return _r(const OtpScreen(), s);
        case '/home':         return _r(const CourierShell(), s);
        case '/documents':    return _r(const DocumentsScreen(), s);
        case '/delivery-proof': return _r(const ProofOfDeliveryScreen(), s);
        case '/onboarding':   return _r(const OnboardingScreen(), s);
        default:              return _r(const CourierShell(), s);
      }
    },
  );

  PageRoute _r(Widget w, RouteSettings s) =>
      MaterialPageRoute(builder: (_) => w, settings: s);
}

// ── Splash gate ───────────────────────────────────────────────────────────────
class _SplashGate extends StatefulWidget {
  const _SplashGate();
  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 900), () async {
      if (!mounted) return;
      final ok = await ApiClient.isAuthenticated;
      var destination = '/auth/phone';
      if (ok) {
        try {
          destination = await ApiClient.instance.postLoginRoute();
        } catch (_) {
          destination = '/home'; // Offline etc. — screens show their own errors
        }
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, destination);
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.brand,
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.delivery_dining, color: Colors.white, size: 80),
      const SizedBox(height: 16),
      const Text('Soko Fetch Courier', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 48),
      const CircularProgressIndicator(color: AppTheme.accent, strokeWidth: 2.5),
    ])),
  );
}

// ── Bottom nav shell ──────────────────────────────────────────────────────────
class CourierShell extends ConsumerStatefulWidget {
  const CourierShell({super.key});
  @override
  ConsumerState<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends ConsumerState<CourierShell> {
  int _index = 0;

  static const _screens = [
    HomeScreen(),
    EarningsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final isOnline = ref.watch(onlineProvider);

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.accent.withOpacity(0.12),
        destinations: [
          NavigationDestination(
            icon: Stack(children: [
              const Icon(Icons.delivery_dining_outlined),
              if (isOnline) Positioned(right: 0, top: 0,
                child: Container(width: 8, height: 8,
                    decoration: const BoxDecoration(color: AppTheme.teal, shape: BoxShape.circle))),
            ]),
            selectedIcon: const Icon(Icons.delivery_dining),
            label: 'Deliver',
          ),
          const NavigationDestination(
            icon: Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label: 'Earnings',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
