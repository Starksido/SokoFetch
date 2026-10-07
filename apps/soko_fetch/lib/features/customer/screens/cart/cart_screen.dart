import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/ui/ui.dart';
import '../../providers/providers.dart';
import '../../widgets/categories.dart';

class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final shopId = notifier.merchantId;
    final shop = shopId == null ? null : ref.watch(merchantDetailProvider(shopId)).valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your cart'),
        actions: [
          if (cart.isNotEmpty)
            TextButton(onPressed: notifier.clear, child: const Text('Clear')),
        ],
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : BottomCtaBar(
              label: 'Go to checkout',
              amount: notifier.subtotal,
              onPressed: () => Navigator.pushNamed(context, '/customer/checkout'),
            ),
      body: cart.isEmpty
          ? EmptyState(
              icon: Icons.shopping_bag_outlined,
              title: 'Your cart is empty',
              message: 'Add items from a shop and they will show up here.',
              actionLabel: 'Browse shops',
              onAction: () => Navigator.popUntil(
                  context, (r) => r.settings.name == '/customer' || r.isFirst),
            )
          : MaxWidth(
              child: ListView(
                padding: const EdgeInsets.only(bottom: SfSpace.lg),
                children: [
                  if (shop != null)
                    ListRow(
                      leading: SfNetworkImage(
                        url: shop.logoUrl ?? shop.bannerUrl,
                        width: 48,
                        height: 48,
                        radius: SfRadius.sm,
                        fallbackIcon: categoryOf(shop.category).icon,
                        fallbackLabel: shop.shopName,
                      ),
                      title: shop.shopName,
                      subtitle: shop.address,
                      trailing: TextButton(
                        onPressed: () => Navigator.pushNamed(
                            context, '/customer/shop', arguments: shop.id),
                        child: const Text('Add items'),
                      ),
                    ),
                  const Divider(),
                  for (final c in cart) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: SfSpace.md, vertical: SfSpace.sm),
                      child: Row(children: [
                        if (c.item.photoUrl != null) ...[
                          SfNetworkImage(
                            url: c.item.photoUrl,
                            width: 56,
                            height: 56,
                            radius: SfRadius.sm,
                            fallbackIcon: Icons.shopping_basket_outlined,
                          ),
                          const SizedBox(width: SfSpace.sm),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(c.item.name, style: text.titleSmall),
                              const SizedBox(height: 2),
                              Text(formatKes(c.lineTotal), style: text.bodyMedium),
                            ],
                          ),
                        ),
                        QtyStepper(
                          quantity: c.quantity,
                          onChanged: (q) => notifier.updateQuantity(c.item.id, q),
                        ),
                      ]),
                    ),
                    const Divider(indent: SfSpace.md, endIndent: SfSpace.md),
                  ],
                  Padding(
                    padding: const EdgeInsets.all(SfSpace.md),
                    child: Column(children: [
                      Row(children: [
                        Expanded(child: Text('Subtotal', style: text.titleSmall)),
                        Text(formatKes(notifier.subtotal), style: text.titleSmall),
                      ]),
                      const SizedBox(height: SfSpace.xxs),
                      Row(children: [
                        Expanded(child: Text('Delivery', style: text.bodyMedium)),
                        Text('Worked out at checkout', style: text.bodyMedium),
                      ]),
                    ]),
                  ),
                ],
              ),
            ),
    );
  }
}
