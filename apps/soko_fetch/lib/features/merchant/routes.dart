import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import 'providers/providers.dart';
import 'screens/dashboard/dashboard_screen.dart';
import 'screens/earnings/earnings_screen.dart';
import 'screens/menu/menu_screen.dart';
import 'screens/onboarding/onboarding_screen.dart';
import 'screens/profile/profile_screen.dart';

Route<dynamic>? merchantRoute(RouteSettings s) {
  final Widget? page = switch (s.name) {
    '/merchant' => const MerchantShell(),
    '/merchant/onboarding' => const OnboardingScreen(),
    _ => null,
  };
  if (page == null) return null;
  return MaterialPageRoute(builder: (_) => page, settings: s);
}

/// Merchant area: bottom navigation on phones, a side rail on tablets.
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
  void initState() {
    super.initState();
    // Shops often run the dashboard on a tablet on its side
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pending = ref.watch(pendingOrderCountProvider);
    Widget ordersIcon(IconData icon) => Badge(
          isLabelVisible: pending > 0,
          label: Text('$pending'),
          backgroundColor: SfColors.brand,
          child: Icon(icon),
        );
    final body = IndexedStack(index: _index, children: _screens);

    if (Breakpoint.of(context) == Breakpoint.expanded) {
      return Scaffold(
        body: Row(children: [
          SafeArea(
            child: NavigationRail(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              labelType: NavigationRailLabelType.all,
              leading: const Padding(
                padding: EdgeInsets.symmetric(vertical: SfSpace.md),
                child: SokoMark(size: 40),
              ),
              destinations: [
                NavigationRailDestination(
                    icon: ordersIcon(Icons.receipt_long_outlined),
                    selectedIcon: ordersIcon(Icons.receipt_long_rounded),
                    label: const Text('Orders')),
                const NavigationRailDestination(
                    icon: Icon(Icons.menu_book_outlined),
                    selectedIcon: Icon(Icons.menu_book_rounded),
                    label: Text('Menu')),
                const NavigationRailDestination(
                    icon: Icon(Icons.bar_chart_outlined),
                    selectedIcon: Icon(Icons.bar_chart_rounded),
                    label: Text('Earnings')),
                const NavigationRailDestination(
                    icon: Icon(Icons.storefront_outlined),
                    selectedIcon: Icon(Icons.storefront_rounded),
                    label: Text('Shop')),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }

    return Scaffold(
      body: body,
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const Divider(),
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            NavigationDestination(
              icon: ordersIcon(Icons.receipt_long_outlined),
              selectedIcon: ordersIcon(Icons.receipt_long_rounded),
              label: 'Orders',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              selectedIcon: Icon(Icons.menu_book_rounded),
              label: 'Menu',
            ),
            const NavigationDestination(
              icon: Icon(Icons.bar_chart_outlined),
              selectedIcon: Icon(Icons.bar_chart_rounded),
              label: 'Earnings',
            ),
            const NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'Shop',
            ),
          ],
        ),
      ]),
    );
  }
}
