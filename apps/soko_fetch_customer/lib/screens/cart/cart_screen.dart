import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cart        = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Cart'),
        actions: [
          if (cart.isNotEmpty)
            TextButton(
              onPressed: () {
                cartNotifier.clear();
                Navigator.pop(context);
              },
              child: const Text('Clear',
                  style: TextStyle(color: AppTheme.accent)),
            ),
        ],
      ),
      body: cart.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_bag_outlined,
                      size: 72, color: AppTheme.mgray),
                  SizedBox(height: 16),
                  Text('Your cart is empty',
                      style: TextStyle(
                          color: AppTheme.mgray, fontSize: 16)),
                ],
              ),
            )
          : Column(children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: cart.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = cart[i];
                    return ListTile(
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 8),
                      title: Text(c.item.name,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          'KES ${c.item.effectivePrice.toStringAsFixed(0)} each'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _QtyBtn(
                              icon: Icons.remove,
                              onTap: () => cartNotifier.updateQuantity(
                                  c.item.id, c.quantity - 1)),
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 12),
                            child: Text('${c.quantity}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16)),
                          ),
                          _QtyBtn(
                              icon: Icons.add,
                              onTap: () => cartNotifier.updateQuantity(
                                  c.item.id, c.quantity + 1)),
                          const SizedBox(width: 12),
                          Text(
                              'KES ${c.lineTotal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.accent)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              // Summary + checkout
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.06),
                        blurRadius: 12,
                        offset: const Offset(0, -4))
                  ],
                ),
                child: Column(children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Subtotal',
                          style: TextStyle(color: AppTheme.mgray)),
                      Text(
                          'KES ${cartNotifier.subtotal.toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Delivery fee',
                          style: TextStyle(color: AppTheme.mgray)),
                      Text('Calculated at checkout',
                          style: TextStyle(
                              color: AppTheme.mgray, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/checkout'),
                    style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(52)),
                    child: const Text('Proceed to Checkout'),
                  ),
                ]),
              ),
            ]),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
              color: AppTheme.accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: AppTheme.accent, size: 15),
        ),
      );
}
