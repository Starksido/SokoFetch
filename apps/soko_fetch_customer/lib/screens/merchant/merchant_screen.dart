import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

class MerchantScreen extends ConsumerWidget {
  const MerchantScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final merchantId = ModalRoute.of(context)!.settings.arguments as String;
    final merchantAsync = ref.watch(merchantDetailProvider(merchantId));
    final cart = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    return merchantAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.accent)),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(),
        body: Center(child: Text('Error: $e')),
      ),
      data: (merchant) {
        final grouped = <String, List<MenuItem>>{};
        for (final item in merchant.menuItems) {
          grouped.putIfAbsent(item.category, () => []).add(item);
        }

        final subtotal =
            cartNotifier.merchantId == merchantId ? cartNotifier.subtotal : 0.0;
        final totalItems =
            cartNotifier.merchantId == merchantId ? cartNotifier.totalItems : 0;

        return Scaffold(
          backgroundColor: AppTheme.lgray,
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 220,
                pinned: true,
                backgroundColor: AppTheme.lgray,
                foregroundColor: AppTheme.brand,
                title: const Text('Soko Fetch'),
                actions: [
                  IconButton(
                    tooltip: 'Share',
                    onPressed: () {},
                    icon: const Icon(Icons.share_outlined),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: [
                      merchant.bannerUrl != null
                          ? CachedNetworkImage(
                              imageUrl: merchant.bannerUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) =>
                                  _HeroFallback(category: merchant.category),
                            )
                          : _HeroFallback(category: merchant.category),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Color(0x99000000)],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Transform.translate(
                  offset: const Offset(0, -28),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _ShopInfoCard(merchant: merchant),
                  ),
                ),
              ),
              if (grouped.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text(
                        'This shop has not added menu items yet.',
                        style: TextStyle(color: AppTheme.mgray),
                      ),
                    ),
                  ),
                )
              else
                for (final entry in grouped.entries) ...[
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _label(entry.key),
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: AppTheme.brand,
                              ),
                            ),
                          ),
                          const Text(
                            'See All',
                            style: TextStyle(
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    sliver: SliverGrid(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.72,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (_, i) {
                          final item = entry.value[i];
                          final qty = cart
                              .where((c) => c.item.id == item.id)
                              .fold(0, (sum, c) => sum + c.quantity);
                          return _MenuItemCard(
                            item: item,
                            qty: qty,
                            onAdd: () => cartNotifier.addItem(item, merchantId),
                            onRemove: () =>
                                cartNotifier.updateQuantity(item.id, qty - 1),
                          );
                        },
                        childCount: entry.value.length,
                      ),
                    ),
                  ),
                ],
              const SliverToBoxAdapter(child: SizedBox(height: 108)),
            ],
          ),
          bottomNavigationBar: subtotal > 0
              ? SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushNamed(context, '/checkout'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryContainer,
                      foregroundColor: const Color(0xFF5F1900),
                      minimumSize: const Size.fromHeight(56),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: const Color(0xFF5F1900),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '$totalItems',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'View Cart',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Ready for checkout',
                                style: TextStyle(fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'KES ${subtotal.toStringAsFixed(0)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : null,
        );
      },
    );
  }

  static String _label(String raw) {
    return raw
        .replaceAll('_', ' ')
        .split(' ')
        .map((word) =>
            word.isEmpty ? word : word[0].toUpperCase() + word.substring(1))
        .join(' ');
  }
}

class _ShopInfoCard extends StatelessWidget {
  final Merchant merchant;

  const _ShopInfoCard({required this.merchant});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        merchant.shopName,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brand,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        merchant.address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppTheme.mgray,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppTheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppTheme.teal, size: 18),
                      const SizedBox(width: 4),
                      Text(
                        merchant.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: AppTheme.teal,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _Tag(label: MerchantScreen._label(merchant.category)),
                const _Tag(label: 'Fast Delivery'),
                if (merchant.minOrderAmount > 0)
                  _Tag(
                      label:
                          'Min KES ${merchant.minOrderAmount.toStringAsFixed(0)}'),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.schedule_rounded,
                    color: AppTheme.mgray, size: 20),
                const SizedBox(width: 8),
                Text(
                  '${merchant.avgPrepMinutes}-25 mins',
                  style: const TextStyle(
                    color: AppTheme.mgray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.pedal_bike_rounded,
                    color: AppTheme.mgray, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'KSh 50 Delivery',
                  style: TextStyle(
                    color: AppTheme.mgray,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  const _MenuItemCard({
    required this.item,
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              width: double.infinity,
              child: item.photoUrl != null
                  ? CachedNetworkImage(
                      imageUrl: item.photoUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _thumb(),
                    )
                  : _thumb(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  item.description ?? MerchantScreen._label(item.category),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppTheme.mgray,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'KSh ${item.effectivePrice.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: AppTheme.accent,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    qty == 0
                        ? _RoundAction(
                            icon: Icons.add_rounded,
                            onTap: item.isAvailable ? onAdd : null,
                          )
                        : Row(
                            children: [
                              _TinyAction(
                                  icon: Icons.remove_rounded, onTap: onRemove),
                              Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 6),
                                child: Text(
                                  '$qty',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                              ),
                              _TinyAction(
                                  icon: Icons.add_rounded, onTap: onAdd),
                            ],
                          ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _thumb() {
    return Container(
      color: AppTheme.primaryFixed,
      child: Icon(Icons.shopping_basket_rounded,
          color: AppTheme.accent.withOpacity(0.45), size: 42),
    );
  }
}

class _Tag extends StatelessWidget {
  final String label;

  const _Tag({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: AppTheme.mgray,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;

  const _RoundAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color:
              onTap == null ? AppTheme.surfaceHigh : AppTheme.primaryContainer,
          shape: BoxShape.circle,
        ),
        child: Icon(icon,
            color: onTap == null ? AppTheme.mgray : const Color(0xFF5F1900)),
      ),
    );
  }
}

class _TinyAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TinyAction({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppTheme.primaryFixed,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppTheme.accent, size: 18),
      ),
    );
  }
}

class _HeroFallback extends StatelessWidget {
  final String category;

  const _HeroFallback({required this.category});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppTheme.primaryFixed,
      child: Icon(
        category == 'pharmacy'
            ? Icons.medical_services_rounded
            : Icons.storefront_rounded,
        size: 90,
        color: AppTheme.accent.withOpacity(0.35),
      ),
    );
  }
}
