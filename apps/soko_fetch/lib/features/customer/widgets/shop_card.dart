import 'package:flutter/material.dart';

import '../../../core/ui/ui.dart';
import '../models/models.dart';
import 'categories.dart';

void openShop(BuildContext context, Merchant shop) =>
    Navigator.pushNamed(context, '/customer/shop', arguments: shop.id);

/// "4.6 · 20 min · Groceries"
class ShopMeta extends StatelessWidget {
  const ShopMeta({super.key, required this.shop});
  final Merchant shop;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: SfSpace.xs,
      runSpacing: SfSpace.xxs,
      children: [
        RatingBadge(rating: shop.rating, count: shop.ratingCount),
        Text('${shop.avgPrepMinutes} min', style: text.bodyMedium),
        Text('·', style: text.bodyMedium),
        Text(categoryOf(shop.category).label, style: text.bodyMedium),
      ],
    );
  }
}

/// Large shop card: wide photo, name, meta line. Uber-Eats-style layout.
class ShopCard extends StatelessWidget {
  const ShopCard({super.key, required this.shop, this.imageHeight = 160});

  final Merchant shop;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final category = categoryOf(shop.category);
    return Semantics(
      button: true,
      label: '${shop.shopName}${shop.isOpen ? '' : ', closed'}',
      child: InkWell(
        borderRadius: SfRadius.mdAll,
        onTap: () => openShop(context, shop),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: imageHeight,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                SfNetworkImage(
                  url: shop.bannerUrl,
                  fallbackIcon: category.icon,
                  fallbackLabel: shop.shopName,
                ),
                if (shop.logoUrl != null)
                  Positioned(
                    left: SfSpace.sm,
                    bottom: SfSpace.sm,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                          color: SfColors.surface, shape: BoxShape.circle),
                      child: ClipOval(
                        child: SfNetworkImage(
                            url: shop.logoUrl,
                            width: 40,
                            height: 40,
                            radius: 20,
                            fallbackIcon: category.icon),
                      ),
                    ),
                  ),
                if (!shop.isOpen)
                  const ClipRRect(
                    borderRadius: SfRadius.mdAll,
                    child: ColoredBox(
                      color: SfColors.scrim,
                      child: Center(
                          child: StatusPill('Closed now', tone: PillTone.dark)),
                    ),
                  ),
              ]),
            ),
            const SizedBox(height: SfSpace.sm),
            Text(shop.shopName,
                style: text.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            const SizedBox(height: SfSpace.xxs),
            ShopMeta(shop: shop),
            if (shop.minOrderAmount > 0) ...[
              const SizedBox(height: 2),
              Text('Min. order ${formatKes(shop.minOrderAmount)}',
                  style: text.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

/// Compact row for search results: square photo, name, meta.
class ShopRow extends StatelessWidget {
  const ShopRow({super.key, required this.shop});
  final Merchant shop;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: () => openShop(context, shop),
      child: Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: SfSpace.md, vertical: SfSpace.sm),
        child: Row(children: [
          SfNetworkImage(
            url: shop.logoUrl ?? shop.bannerUrl,
            width: 64,
            height: 64,
            radius: SfRadius.sm,
            fallbackIcon: categoryOf(shop.category).icon,
            fallbackLabel: shop.shopName,
          ),
          const SizedBox(width: SfSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shop.shopName,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: SfSpace.xxs),
              ShopMeta(shop: shop),
            ]),
          ),
          if (!shop.isOpen) const StatusPill('Closed'),
        ]),
      ),
    );
  }
}

/// Grey placeholders shaped like shop cards.
class ShopCardSkeleton extends StatelessWidget {
  const ShopCardSkeleton({super.key, this.imageHeight = 160});
  final double imageHeight;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Skeleton(height: imageHeight, radius: SfRadius.md),
          const SizedBox(height: SfSpace.sm),
          const Skeleton(width: 180),
          const SizedBox(height: SfSpace.xs),
          const Skeleton(width: 120, height: 12),
        ],
      );
}
