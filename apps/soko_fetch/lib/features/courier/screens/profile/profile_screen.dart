import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session.dart';
import '../../../../core/ui/ui.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  static (String, PillTone) _status(String s) => switch (s) {
        'active' => ('Approved', PillTone.success),
        'approved' => ('Approved', PillTone.success),
        'documents_submitted' || 'under_review' => ('In review', PillTone.warning),
        'rejected' => ('Not approved', PillTone.danger),
        'suspended' || 'deactivated' => ('Suspended', PillTone.danger),
        _ => ('Documents needed', PillTone.neutral),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profileAsync = ref.watch(courierProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profileAsync.when(
        loading: () => const LoadingList(count: 3),
        error: (_, __) =>
            ErrorState(onRetry: () => ref.invalidate(courierProfileProvider)),
        data: (p) {
          final (label, tone) = _status(p.status);
          final name = p.fullName ?? 'Rider';
          return MaxWidth(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.all(SfSpace.md),
                child: Row(children: [
                  InitialsAvatar(name: name, size: 64),
                  const SizedBox(width: SfSpace.md),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: text.headlineSmall),
                          const SizedBox(height: SfSpace.xxs),
                          StatusPill(label, tone: tone),
                        ]),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    SfSpace.md, 0, SfSpace.md, SfSpace.md),
                child: Row(children: [
                  Expanded(
                      child: StatTile(
                          label: 'Rating',
                          value: p.rating.toStringAsFixed(1),
                          icon: Icons.star_rounded)),
                  const SizedBox(width: SfSpace.sm),
                  Expanded(
                      child: StatTile(
                          label: 'Deliveries',
                          value: '${p.totalDeliveries}',
                          icon: Icons.local_shipping_outlined)),
                  const SizedBox(width: SfSpace.sm),
                  Expanded(
                      child: StatTile(
                          label: 'Earned',
                          value: formatKes(p.totalEarned),
                          icon: Icons.payments_outlined)),
                ]),
              ),
              const SectionGap(),
              if (!p.isApproved)
                ListRow(
                  leading: const Icon(Icons.upload_file_outlined),
                  title: 'Verification documents',
                  subtitle: '${p.documents.length} of 5 uploaded',
                  trailing: const Icon(Icons.chevron_right_rounded,
                      color: SfColors.inkFaint),
                  onTap: () => Navigator.pushNamed(context, '/courier/documents'),
                ),
              ListRow(
                leading: const Icon(Icons.two_wheeler_outlined),
                title: 'Vehicle',
                subtitle: [
                  p.vehicleType.replaceAll('_', ' '),
                  if (p.vehiclePlate != null) p.vehiclePlate!,
                ].join(' · '),
              ),
              if (p.payoutPhone != null)
                ListRow(
                  leading: const Icon(Icons.phone_iphone_rounded),
                  title: 'M-Pesa payouts',
                  subtitle: p.payoutPhone,
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
