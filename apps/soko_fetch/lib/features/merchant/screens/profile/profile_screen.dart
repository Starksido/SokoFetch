import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session.dart';
import '../../../../core/ui/ui.dart';
import '../../providers/providers.dart';
import '../onboarding/onboarding_screen.dart' show kMerchantCategories;

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static (String, PillTone) _status(String s) => switch (s) {
        'active' => ('Live', PillTone.success),
        'pending_review' => ('In review', PillTone.warning),
        'suspended' => ('Suspended', PillTone.danger),
        'deactivated' => ('Closed', PillTone.danger),
        _ => (s.replaceAll('_', ' '), PillTone.neutral),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profileAsync = ref.watch(merchantProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shop')),
      body: profileAsync.when(
        loading: () => const LoadingList(count: 3),
        error: (_, __) =>
            ErrorState(onRetry: () => ref.invalidate(merchantProfileProvider)),
        data: (p) {
          final (label, tone) = _status(p.status);
          return MaxWidth(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.all(SfSpace.md),
                child: Row(children: [
                  SfNetworkImage(
                    url: p.logoUrl,
                    width: 64,
                    height: 64,
                    radius: SfRadius.md,
                    fallbackIcon: Icons.storefront_outlined,
                    fallbackLabel: p.shopName,
                  ),
                  const SizedBox(width: SfSpace.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p.shopName, style: text.headlineSmall),
                      const SizedBox(height: SfSpace.xxs),
                      StatusPill(label, tone: tone),
                    ]),
                  ),
                ]),
              ),
              if (p.isPending)
                const Padding(
                  padding: EdgeInsets.fromLTRB(SfSpace.md, 0, SfSpace.md, SfSpace.md),
                  child: InlineMessage(
                    "Your shop is being reviewed. Customers will see it once it's approved.",
                    isError: false,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SfSpace.md, 0, SfSpace.md, SfSpace.md),
                child: Row(children: [
                  Expanded(
                      child: StatTile(
                          label: 'Rating',
                          value: p.ratingCount == 0 ? 'New' : p.rating.toStringAsFixed(1),
                          icon: Icons.star_rounded)),
                  const SizedBox(width: SfSpace.sm),
                  Expanded(
                      child: StatTile(
                          label: 'Reviews',
                          value: '${p.ratingCount}',
                          icon: Icons.reviews_outlined)),
                  const SizedBox(width: SfSpace.sm),
                  Expanded(
                      child: StatTile(
                          label: 'Prep time',
                          value: '${p.avgPrepMinutes} min',
                          icon: Icons.timer_outlined)),
                ]),
              ),
              const SectionGap(),
              ListRow(
                leading: const Icon(Icons.place_outlined),
                title: 'Address',
                subtitle: p.address,
              ),
              ListRow(
                leading: const Icon(Icons.category_outlined),
                title: 'Category',
                subtitle: kMerchantCategories[p.category] ??
                    p.category.replaceAll('_', ' '),
              ),
              ListRow(
                leading: const Icon(Icons.percent_rounded),
                title: 'Soko Fetch fee',
                subtitle: '${p.commissionRate.toStringAsFixed(0)}% of each order',
              ),
              ListRow(
                leading: const Icon(Icons.phone_iphone_rounded),
                title: 'M-Pesa payouts',
                subtitle: p.payoutPhone ?? 'Not set',
              ),
              const SectionGap(),
              ListRow(
                leading: const Icon(Icons.logout_rounded, color: SfColors.danger),
                title: 'Log out',
                titleStyle: text.titleSmall!.copyWith(color: SfColors.danger),
                onTap: Session.logout,
              ),
            ]),
          );
        },
      ),
    );
  }
}
