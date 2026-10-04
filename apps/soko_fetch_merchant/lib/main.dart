import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'config/app_theme.dart';
import 'network/api_client.dart';
import 'providers/providers.dart';
import 'screens/auth/auth_screens.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/menu/menu_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/profile/profile_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const ProviderScope(child: MerchantApp()));
}

class MerchantApp extends StatelessWidget {
  const MerchantApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:        'Soko Fetch Merchant',
      debugShowCheckedModeBanner: false,
      theme:        AppTheme.light,
      initialRoute: '/',
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/':
            return MaterialPageRoute(
                builder: (_) => const _SplashGate(), settings: settings);
          case '/auth/phone':
            return MaterialPageRoute(
                builder: (_) => const PhoneScreen(), settings: settings);
          case '/auth/otp':
            return MaterialPageRoute(
                builder: (_) => const OtpScreen(), settings: settings);
          case '/dashboard':
            return MaterialPageRoute(
                builder: (_) => const MerchantShell(), settings: settings);
          case '/onboarding':
            return MaterialPageRoute(
                builder: (_) => const OnboardingScreen(), settings: settings);
          default:
            return MaterialPageRoute(
                builder: (_) => const MerchantShell(), settings: settings);
        }
      },
    );
  }
}

// ── Splash gate — checks session ──────────────────────────────────────────────
class _SplashGate extends StatefulWidget {
  const _SplashGate();
  @override
  State<_SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<_SplashGate> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    await Future.delayed(const Duration(milliseconds: 800));
    if (!mounted) return;
    final loggedIn = await ApiClient.isAuthenticated;
    var destination = '/auth/phone';
    if (loggedIn) {
      try {
        destination = await ApiClient.instance.postLoginRoute();
      } catch (_) {
        destination = '/dashboard'; // Offline etc. — screens show their own errors
      }
    }
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, destination);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppTheme.brand,
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.storefront_outlined,
                color: Colors.white, size: 72),
            const SizedBox(height: 16),
            const Text('Soko Fetch Merchant',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
                color: AppTheme.accent, strokeWidth: 2.5),
          ]),
        ),
      );
}

// ── Main shell with bottom navigation ────────────────────────────────────────
class MerchantShell extends ConsumerStatefulWidget {
  const MerchantShell({super.key});
  @override
  ConsumerState<MerchantShell> createState() => _MerchantShellState();
}

class _MerchantShellState extends ConsumerState<MerchantShell> {
  int _index = 0;

  static const _screens = [
    DashboardScreen(),
    MenuScreen(),
    EarningsScreen(),
    ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final pendingCount = ref.watch(pendingOrderCountProvider);

    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: Colors.white,
        indicatorColor: AppTheme.accent.withOpacity(0.12),
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.dashboard_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: pendingCount > 0,
              label: Text('$pendingCount'),
              child: const Icon(Icons.dashboard),
            ),
            label: 'Orders',
          ),
          const NavigationDestination(
            icon:         Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label:        'Menu',
          ),
          const NavigationDestination(
            icon:         Icon(Icons.bar_chart_outlined),
            selectedIcon: Icon(Icons.bar_chart),
            label:        'Earnings',
          ),
          const NavigationDestination(
            icon:         Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store),
            label:        'Profile',
          ),
        ],
      ),
    );
  }
}
