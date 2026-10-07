import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import '../../core/models.dart' show kDocLabels, kRequiredDocs;
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

    return Scaffold(
      appBar: AppBar(title: const Text('Review rider')),
      body: rider.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (e, _) => Center(child: Text(errorMessage(e, 'Could not load.'))),
        data: (r) {
          final p = r.profile;
          final uploaded = {for (final d in p.documents) d.docType};
          final missing = kRequiredDocs.where((d) => !uploaded.contains(d));
          final name = p.fullName ?? 'Rider';
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                '${p.vehicleType.replaceAll('_', ' ')}'
                '${p.vehiclePlate != null ? ' · ${p.vehiclePlate}' : ''}'
                ' · ${p.status.replaceAll('_', ' ')}'
                ' · signed up ${formatDate(r.createdAt)}',
                style: const TextStyle(color: AppTheme.mgray),
              ),
              if (r.rejectionReason != null) ...[
                const SizedBox(height: 8),
                Text('Previously rejected: ${r.rejectionReason}',
                    style: const TextStyle(color: AppTheme.red)),
              ],
              if (missing.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Missing: ${missing.map((d) => kDocLabels[d] ?? d).join(', ')}',
                  style: const TextStyle(color: AppTheme.gold),
                ),
              ],
              const SizedBox(height: 16),
              for (final doc in p.documents)
                _DocumentTile(courierId: p.id, docType: doc.docType),
              const SizedBox(height: 16),
              ApproveRejectRow(
                onApprove: () => _act(context, ref,
                    () => AdminApi.approveRider(p.id), '$name approved'),
                onReject: () async {
                  final reason = await askRejectReason(context, 'rider');
                  if (reason == null || !context.mounted) return;
                  await _act(context, ref,
                      () => AdminApi.rejectRider(p.id, reason), '$name rejected');
                },
              ),
            ],
          );
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          SizedBox(
            height: 200,
            child: bytes.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: AppTheme.accent)),
              error: (e, _) => Center(
                  child: Text(errorMessage(e, 'Could not load document'),
                      style: const TextStyle(color: AppTheme.mgray))),
              data: (b) {
                final image = Uint8List.fromList(b);
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => Scaffold(
                      backgroundColor: Colors.black,
                      appBar: AppBar(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          title: Text(label,
                              style: const TextStyle(color: Colors.white))),
                      body: InteractiveViewer(
                          child: Center(child: Image.memory(image))),
                    ),
                  )),
                  child: Image.memory(image,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Center(
                          child: Text('Not an image',
                              style: TextStyle(color: AppTheme.mgray)))),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
