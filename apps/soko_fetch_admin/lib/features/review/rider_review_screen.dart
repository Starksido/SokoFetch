import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/models.dart' show kDocLabels, kRequiredDocs;
import '../../core/ui/ui.dart';
import 'admin_api.dart';
import 'admin_home_screen.dart' show ApproveRejectRow, askRejectReason;

class RiderReviewScreen extends ConsumerWidget {
  const RiderReviewScreen({super.key});

  Future<void> _act(BuildContext context, WidgetRef ref,
      Future<void> Function() action, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await action();
      ref.invalidate(pendingRidersProvider);
      messenger.showSnackBar(SnackBar(content: Text(done)));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = ModalRoute.of(context)!.settings.arguments as String;
    final rider = ref.watch(riderProvider(id));
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Review rider')),
      body: rider.when(
        loading: () => const SfLoader(),
        error: (e, _) => ErrorState(
          message: errorMessage(e, 'Could not load.'),
          onRetry: () => ref.invalidate(riderProvider(id)),
        ),
        data: (r) {
          final p = r.profile;
          final uploaded = {for (final d in p.documents) d.docType};
          final missing = kRequiredDocs.where((d) => !uploaded.contains(d));
          final name = p.fullName ?? 'Rider';
          return Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(SfSpace.md),
                children: [
                  Row(children: [
                    Expanded(child: Text(name, style: text.headlineSmall)),
                    const SizedBox(width: SfSpace.xs),
                    StatusPill(p.status.replaceAll('_', ' '),
                        tone: PillTone.warning),
                  ]),
                  const SizedBox(height: SfSpace.xxs),
                  Text(
                    '${p.vehicleType.replaceAll('_', ' ')}'
                    '${p.vehiclePlate != null ? ' · ${p.vehiclePlate}' : ''}'
                    ' · signed up ${formatDate(r.createdAt)}',
                    style: text.bodyMedium,
                  ),
                  if (missing.isNotEmpty) ...[
                    const SizedBox(height: SfSpace.sm),
                    InlineMessage(
                        'Missing: ${missing.map((d) => kDocLabels[d] ?? d).join(', ')}'),
                  ],
                  if (r.rejectionReason != null) ...[
                    const SizedBox(height: SfSpace.sm),
                    InlineMessage('Previously rejected: ${r.rejectionReason}',
                        isError: false),
                  ],
                  const SizedBox(height: SfSpace.lg),
                  Text('Documents', style: text.titleMedium),
                  const SizedBox(height: SfSpace.sm),
                  if (p.documents.isEmpty)
                    Text('No documents uploaded yet.', style: text.bodyMedium)
                  else
                    LayoutBuilder(builder: (_, box) {
                      // Two documents side by side on wide screens
                      final columns = box.maxWidth >= 600 ? 2 : 1;
                      final width =
                          (box.maxWidth - SfSpace.sm * (columns - 1)) / columns;
                      return Wrap(
                        spacing: SfSpace.sm,
                        runSpacing: SfSpace.sm,
                        children: [
                          for (final doc in p.documents)
                            SizedBox(
                              width: width,
                              child: _DocumentTile(
                                  courierId: p.id, docType: doc.docType),
                            ),
                        ],
                      );
                    }),
                ],
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                  color: SfColors.surface, boxShadow: SfShadow.bar),
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.all(SfSpace.md),
                child: ApproveRejectRow(
                  onApprove: () => _act(context, ref,
                      () => AdminApi.approveRider(p.id), '$name approved'),
                  onReject: () async {
                    final reason = await askRejectReason(context, 'rider');
                    if (reason == null || !context.mounted) return;
                    await _act(context, ref,
                        () => AdminApi.rejectRider(p.id, reason), '$name rejected');
                  },
                ),
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _DocumentTile extends ConsumerWidget {
  const _DocumentTile({required this.courierId, required this.docType});
  final String courierId, docType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes =
        ref.watch(riderDocumentProvider((courierId: courierId, docType: docType)));
    final label = kDocLabels[docType] ?? docType;
    final text = Theme.of(context).textTheme;

    Widget notice(IconData icon, String message) => Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: SfColors.inkFaint),
            const SizedBox(height: SfSpace.xs),
            Text(message, style: text.bodySmall, textAlign: TextAlign.center),
          ],
        );

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 200,
            color: SfColors.surface2,
            child: bytes.when(
              loading: () => const SfLoader(),
              error: (e, _) => notice(Icons.broken_image_outlined,
                  errorMessage(e, 'Could not load document')),
              data: (b) {
                final image = Uint8List.fromList(b);
                return InkWell(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          title: Text(label,
                              style: text.titleLarge!
                                  .copyWith(color: Colors.white))),
                      body: InteractiveViewer(
                          child: Center(child: Image.memory(image))),
                    ),
                  )),
                  child: Image.memory(image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          notice(Icons.description_outlined, 'Not an image')),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: SfSpace.md, vertical: SfSpace.sm),
            child: Row(children: [
              Expanded(child: Text(label, style: text.titleSmall)),
              const Icon(Icons.zoom_in_rounded,
                  size: 20, color: SfColors.inkMuted),
            ]),
          ),
        ],
      ),
    );
  }
}
