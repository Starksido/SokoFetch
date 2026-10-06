import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import 'providers/providers.dart';
import 'screens/delivery/proof_screen.dart';
import 'screens/dispatch/home_screen.dart';
import 'screens/documents/documents_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/profile/profile_screen.dart';

Route<dynamic>? courierRoute(RouteSettings s) {
  final Widget? page = switch (s.name) {
    '/courier' => const CourierShell(),
    '/courier/onboarding' => const OnboardingScreen(),
    '/courier/documents' => const DocumentsScreen(),
    '/courier/delivery-proof' => const ProofOfDeliveryScreen(),
    _ => null,
  };
  if (page == null) return null;
  return MaterialPageRoute(builder: (_) => page, settings: s);
}

// ── Bottom nav shell ──────────────────────────────────────────────────────────
class CourierShell extends ConsumerStatefulWidget {
  const CourierShell({super.key});
  @override
  ConsumerState<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends ConsumerState<CourierShell> {
  static const _profileTab = 2;
  int _index = 0;

  late final List<Widget> _screens = [
    HomeScreen(onOpenProfile: () => setState(() => _index = _profileTab)),
    const EarningsScreen(),
    const ProfileScreen(),
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
        indicatorColor: AppTheme.accent.withValues(alpha: 0.12),
        destinations: [
          NavigationDestination(
            icon: Stack(children: [
              const Icon(Icons.delivery_dining_outlined),
              if (isOnline)
                Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppTheme.teal, shape: BoxShape.circle))),
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
