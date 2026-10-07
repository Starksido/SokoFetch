import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/session.dart';
import '../../core/ui/ui.dart';
import 'admin_api.dart';

/// Admins approve or reject new shops and riders.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: SfSpace.md,
            title: const Row(children: [
              SokoMark(size: 32),
              SizedBox(width: SfSpace.sm),
              Flexible(
                  child: Text('Soko Fetch Admin',
                      overflow: TextOverflow.ellipsis)),
            ]),
            actions: const [
              IconButton(
                tooltip: 'Log out',
                icon: Icon(Icons.logout_rounded),
                onPressed: Session.logout,
              ),
              SizedBox(width: SfSpace.xs),
            ],
            bottom: const TabBar(
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
          style: TextButton.styleFrom(foregroundColor: SfColors.danger),
          onPressed: () {
            if (formKey.currentState!.validate()) {
              Navigator.pop(dialogContext, ctrl.text.trim());
            }
          },
          child: const Text('Reject'),
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

/// Keeps a centred state scrollable so pull-to-refresh still works.
class _Pullable extends StatelessWidget {
  const _Pullable(this.child);
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (_, box) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: child,
          ),
        ),
      );
}

/// The list of pending sign-ups, or its empty, loading and error states.
class _ReviewList<T> extends ConsumerWidget {
  const _ReviewList({
    required this.provider,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.itemBuilder,
  });

  final AutoDisposeFutureProvider<List<T>> provider;
  final IconData emptyIcon;
  final String emptyTitle;
  final Widget Function(T item) itemBuilder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(provider);
    return RefreshIndicator(
      onRefresh: () => ref.refresh(provider.future),
      child: items.when(
        loading: () => const SfLoader(),
        error: (e, _) => _Pullable(ErrorState(
          message: errorMessage(e, 'Could not load.'),
          onRetry: () => ref.invalidate(provider),
        )),
        data: (list) => list.isEmpty
            ? _Pullable(EmptyState(
                icon: emptyIcon,
                title: emptyTitle,
                message: 'New sign-ups will appear here.',
              ))
            : ListView.separated(
                padding: const EdgeInsets.all(SfSpace.md),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: SfSpace.sm),
                itemBuilder: (_, i) =>
                    MaxWidth(maxWidth: 720, child: itemBuilder(list[i])),
              ),
      ),
    );
  }
}

// ── Shops ─────────────────────────────────────────────────────────────────────
class _ShopsTab extends StatelessWidget {
  const _ShopsTab();

  @override
  Widget build(BuildContext context) => _ReviewList<PendingShop>(
        provider: pendingShopsProvider,
        emptyIcon: Icons.storefront_outlined,
        emptyTitle: 'No shops waiting for approval',
        itemBuilder: (shop) => _ShopCard(shop: shop),
      );
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop});
  final PendingShop shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SfSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const _Avatar(icon: Icons.storefront_outlined),
              const SizedBox(width: SfSpace.sm),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shop.shopName, style: text.titleMedium),
                      const SizedBox(height: 2),
                      Text(
                          '${shop.category.replaceAll('_', ' ')} · signed up ${formatDate(shop.createdAt)}',
                          style: text.bodySmall),
                    ]),
              ),
              const SizedBox(width: SfSpace.xs),
              const StatusPill('Pending', tone: PillTone.warning),
            ]),
            const SizedBox(height: SfSpace.sm),
            _Line(Icons.location_on_outlined, '${shop.address}, ${shop.city}'),
            if (shop.payoutPhone != null)
              _Line(Icons.phone_android_outlined, 'Payout ${shop.payoutPhone}'),
            if (shop.description != null && shop.description!.isNotEmpty)
              _Line(Icons.notes_outlined, shop.description!),
            const SizedBox(height: SfSpace.md),
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
class _RidersTab extends StatelessWidget {
  const _RidersTab();

  @override
  Widget build(BuildContext context) => _ReviewList<RiderReview>(
        provider: pendingRidersProvider,
        emptyIcon: Icons.delivery_dining_outlined,
        emptyTitle: 'No riders waiting for review',
        itemBuilder: (r) {
          final p = r.profile;
          return Card(
            clipBehavior: Clip.antiAlias,
            child: Builder(
              builder: (context) => ListRow(
                leading: const _Avatar(icon: Icons.delivery_dining_outlined),
                title: p.fullName ?? 'Unnamed rider',
                subtitle: '${p.vehicleType.replaceAll('_', ' ')}'
                    '${p.vehiclePlate != null ? ' · ${p.vehiclePlate}' : ''}'
                    ' · ${p.documents.length} documents',
                trailing: const Icon(Icons.chevron_right_rounded,
                    color: SfColors.inkFaint),
                onTap: () =>
                    Navigator.pushNamed(context, '/rider', arguments: p.id),
              ),
            ),
          );
        },
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
            color: SfColors.accentSoft, shape: BoxShape.circle),
        child: Icon(icon, color: SfColors.accentStrong, size: 22),
      );
}

class _Line extends StatelessWidget {
  const _Line(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: SfSpace.xxs),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: SfColors.inkMuted),
          const SizedBox(width: SfSpace.xs),
          Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
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
    if (_busy) return const SizedBox(height: 52, child: SfLoader());
    return Row(children: [
      Expanded(
        child: SfButton.destructive(
            label: 'Reject', onPressed: () => _run(widget.onReject)),
      ),
      const SizedBox(width: SfSpace.sm),
      Expanded(
        child: SfButton.primary(
            label: 'Approve',
            icon: Icons.check_rounded,
            onPressed: () => _run(widget.onApprove)),
      ),
    ]);
  }
}
