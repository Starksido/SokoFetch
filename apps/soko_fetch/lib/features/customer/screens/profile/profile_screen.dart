import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session.dart';
import '../../../../core/ui/ui.dart';
import '../../providers/providers.dart';
import '../../widgets/address_sheet.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, this.onOpenOrders});

  /// Switches the shell to the Orders tab (when shown as a tab).
  final VoidCallback? onOpenOrders;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final profile = ref.watch(customerProfileProvider).valueOrNull;
    final user = ref.watch(currentUserProvider);
    final address = ref.watch(selectedAddressProvider);
    final name = profile?.fullName ?? 'Your account';
    final contact = user?.phone ?? profile?.email ?? user?.email;

    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: MaxWidth(
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(SfSpace.md),
              child: Row(children: [
                InitialsAvatar(name: name, size: 64),
                const SizedBox(width: SfSpace.md),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, style: text.headlineSmall),
                    if (contact != null) Text(contact, style: text.bodyMedium),
                  ]),
                ),
              ]),
            ),
            const SectionGap(),
            ListRow(
              leading: const Icon(Icons.receipt_long_outlined),
              title: 'Orders',
              trailing: const Icon(Icons.chevron_right_rounded, color: SfColors.inkFaint),
              onTap: onOpenOrders ??
                  () => Navigator.pushNamed(context, '/customer/orders'),
            ),
            ListRow(
              leading: const Icon(Icons.place_outlined),
              title: 'Delivery addresses',
              subtitle: address == null ? 'None saved yet' : address.fullAddress,
              trailing: const Icon(Icons.chevron_right_rounded, color: SfColors.inkFaint),
              onTap: () => showAddressSheet(context),
            ),
            const SectionGap(),
            ListRow(
              leading: const Icon(Icons.logout_rounded, color: SfColors.danger),
              title: 'Log out',
              titleStyle: text.titleSmall!.copyWith(color: SfColors.danger),
              onTap: Session.logout,
            ),
          ],
        ),
      ),
    );
  }
}
