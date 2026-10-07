import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'admin_api.dart';

/// Admins approve or reject new shops and riders.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Soko Fetch Admin'),
            actions: const [
              IconButton(
                tooltip: 'Log out',
                icon: Icon(Icons.logout),
                onPressed: Session.logout,
              ),
            ],
            bottom: const TabBar(
              labelColor: AppTheme.accent,
              indicatorColor: AppTheme.accent,
              tabs: [
                Tab(icon: Icon(Icons.storefront_outlined), text: 'Shops'),
                Tab(icon: Icon(Icons.delivery_dining_outlined), text: 'Riders'),
              ],
            ),
          ),
          body: const TabBarView(children: [_ShopsTab(), _RidersTab()]),
        ),
      );
}

/// Asks for a rejection reason (3–500 characters, as the server requires).
Future<String?> askRejectReason(BuildContext context, String what) {
  final ctrl = TextEditingController();
  final formKey = GlobalKey<FormState>();
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text('Reject $what'),
      content: Form(
        key: formKey,
        child: TextFormField(
          controller: ctrl,
          autofocus: true,
          maxLength: 500,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason'),
          validator: (v) => (v == null || v.trim().length < 3)
              ? 'Give a short reason'
              : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, ctrl.text.trim());
            }
          },
          child: const Text('Reject', style: TextStyle(color: AppTheme.red)),
        ),
      ],
    ),
  ).whenComplete(ctrl.dispose);
}

/// Runs an approve/reject call, shows the outcome and refreshes [list].
Future<void> runAdminAction(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action, {
  required String done,
  required ProviderOrFamily list,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
  }
  ref.invalidate(list);
}

class _Empty extends StatelessWidget {
  const _Empty(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => ListView(children: [
        const SizedBox(height: 120),
        const Icon(Icons.check_circle_outline, size: 56, color: AppTheme.teal),
        const SizedBox(height: 12),
        Center(
            child: Text(message, style: const TextStyle(color: AppTheme.mgray))),
      ]);
}

class _LoadError extends StatelessWidget {
  const _LoadError(this.error, this.onRetry);
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(errorMessage(error, 'Could not load.')),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      );
}

// ── Shops ─────────────────────────────────────────────────────────────────────
class _ShopsTab extends ConsumerWidget {
  const _ShopsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shops = ref.watch(pendingShopsProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(pendingShopsProvider.future),
      child: shops.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) =>
            _LoadError(e, () => ref.invalidate(pendingShopsProvider)),
        data: (list) => list.isEmpty
            ? const _Empty('No shops waiting for approval')
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) => _ShopCard(shop: list[i]),
              ),
      ),
    );
  }
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop});
  final PendingShop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(shop.shopName,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            Text(
                '${shop.category.replaceAll('_', ' ')} · signed up ${formatDate(shop.createdAt)}',
                style: const TextStyle(color: AppTheme.mgray, fontSize: 12)),
            const SizedBox(height: 10),
            _Line(Icons.location_on_outlined, '${shop.address}, ${shop.city}'),
            if (shop.payoutPhone != null)
              _Line(Icons.phone_android_outlined, 'Payout ${shop.payoutPhone}'),
            if (shop.description != null && shop.description!.isNotEmpty)
              _Line(Icons.notes_outlined, shop.description!),
            const SizedBox(height: 12),
            ApproveRejectRow(
              onApprove: () => runAdminAction(
                context, ref, () => AdminApi.approveShop(shop.id),
                done: '${shop.shopName} approved',
                list: pendingShopsProvider,
              ),
              onReject: () async {
                final reason = await askRejectReason(context, 'shop');
                if (reason == null || !context.mounted) return;
                await runAdminAction(
                  context, ref, () => AdminApi.rejectShop(shop.id, reason),
                  done: '${shop.shopName} rejected',
                  list: pendingShopsProvider,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ── Riders ────────────────────────────────────────────────────────────────────
class _RidersTab extends ConsumerWidget {
  const _RidersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final riders = ref.watch(pendingRidersProvider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(pendingRidersProvider.future),
      child: riders.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) =>
            _LoadError(e, () => ref.invalidate(pendingRidersProvider)),
        data: (list) => list.isEmpty
            ? const _Empty('No riders waiting for review')
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final r = list[i];
                  final p = r.profile;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: AppTheme.primaryFixed,
                        child: Icon(Icons.delivery_dining,
                            color: AppTheme.accent),
                      ),
                      title: Text(p.fullName ?? 'Unnamed rider',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                          '${p.vehicleType.replaceAll('_', ' ')}'
                          '${p.vehiclePlate != null ? ' · ${p.vehiclePlate}' : ''}'
                          ' · ${p.documents.length} documents'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.pushNamed(
                          context, '/rider',
                          arguments: p.id),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: AppTheme.mgray),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ]),
      );
}

class ApproveRejectRow extends StatefulWidget {
  const ApproveRejectRow(
      {super.key, required this.onApprove, required this.onReject});
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;

  @override
  State<ApproveRejectRow> createState() => _ApproveRejectRowState();
}

class _ApproveRejectRowState extends State<ApproveRejectRow> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Center(
          child: CircularProgressIndicator(color: AppTheme.accent));
    }
    return Row(children: [
      Expanded(
        child: OutlinedButton(
          onPressed: () => _run(widget.onReject),
          style: OutlinedButton.styleFrom(foregroundColor: AppTheme.red),
          child: const Text('Reject'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: ElevatedButton(
          onPressed: () => _run(widget.onApprove),
          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
          child: const Text('Approve'),
        ),
      ),
    ]);
  }
}
