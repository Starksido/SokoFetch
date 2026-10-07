import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui/ui.dart';
import 'providers/providers.dart';
import 'screens/browse/browse_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/orders/orders_screen.dart';
import 'screens/profile/profile_screen.dart';

/// Customer area: Home, Browse, Orders, Account, with the cart one tap away.
class CustomerShell extends ConsumerStatefulWidget {
  const CustomerShell({super.key});

  @override
  ConsumerState<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends ConsumerState<CustomerShell> {
  static const _browse = 1, _orders = 2;
  int _index = 0;
  final _browseKey = GlobalKey<BrowseScreenState>();

  void _go(int i) => setState(() => _index = i);

  late final List<Widget> _tabs = [
    HomeScreen(onSearch: () {
      _go(_browse);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _browseKey.currentState?.focusSearch());
    }),
    BrowseScreen(key: _browseKey),
    const OrdersScreen(),
    ProfileScreen(onOpenOrders: () => _go(_orders)),
  ];

  @override
  Widget build(BuildContext context) {
    ref.watch(cartProvider);
    final cart = ref.read(cartProvider.notifier);

    return Scaffold(
      body: IndexedStack(index: _index, children: _tabs),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (cart.totalItems > 0 && _index != _orders)
          BottomCtaBar(
            label: 'View cart',
            count: cart.totalItems,
            amount: cart.subtotal,
            onPressed: () => Navigator.pushNamed(context, '/customer/cart'),
          ),
        const Divider(),
        NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) {
            if (i == _orders) ref.invalidate(ordersProvider);
            _go(i);
          },
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home_rounded),
                label: 'Home'),
            NavigationDestination(
                icon: Icon(Icons.search_rounded), label: 'Browse'),
            NavigationDestination(
                icon: Icon(Icons.receipt_long_outlined),
                selectedIcon: Icon(Icons.receipt_long_rounded),
                label: 'Orders'),
            NavigationDestination(
                icon: Icon(Icons.person_outline_rounded),
                selectedIcon: Icon(Icons.person_rounded),
                label: 'Account'),
          ],
        ),
      ]),
    );
  }
}
