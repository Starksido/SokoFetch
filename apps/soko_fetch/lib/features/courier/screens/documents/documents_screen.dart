import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';
import '../../providers/providers.dart';

class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});
  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  final Map<String, bool> _uploaded   = {};
  final Map<String, bool> _uploading  = {};
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadUploaded();
  }

  void _loadUploaded() {
    final profile = ref.read(courierProfileProvider).valueOrNull;
    if (profile != null) {
      for (final doc in profile.documents) {
        _uploaded[doc.docType] = true;
      }
    }
  }

  Future<void> _pick(String docType) async {
    final result = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920, maxHeight: 1920,
      imageQuality: 85,
    );
    if (result == null) return;

    setState(() => _uploading[docType] = true);

    try {
      final bytes = await result.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        _showSnack('Image too large. Maximum size is 5MB.', error: true);
        return;
      }

      final formData = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: result.name),
      });

      await ApiClient.instance.dio.post(
        '/courier/documents/upload?doc_type=$docType',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );

      setState(() => _uploaded[docType] = true);
      ref.invalidate(courierProfileProvider);

      // Check if all uploaded
      if (kRequiredDocs.every((d) => _uploaded[d] == true)) {
        _showSnack('All documents uploaded! Pending admin review.');
      } else {
        _showSnack('${kDocLabels[docType]} uploaded.');
      }
    } catch (e) {
      _showSnack('Upload failed. Please try again.', error: true);
    } finally {
      if (mounted) setState(() => _uploading[docType] = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? SfColors.danger : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final profileAsync = ref.watch(courierProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: profileAsync.when(
        loading: () => const LoadingList(),
        error: (_, __) =>
            ErrorState(onRetry: () => ref.invalidate(courierProfileProvider)),
        data: (profile) {
          // Merge server-side uploads with local state
          for (final doc in profile.documents) {
            _uploaded[doc.docType] = true;
          }
          final uploadedCount =
              kRequiredDocs.where((d) => _uploaded[d] == true).length;
          final allDone = uploadedCount == kRequiredDocs.length;

          return MaxWidth(
            child: ListView(children: [
              Padding(
                padding: const EdgeInsets.all(SfSpace.md),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Get verified', style: text.headlineSmall),
                  const SizedBox(height: SfSpace.xxs),
                  Text('Clear photos of 5 documents. We review them within 24 hours.',
                      style: text.bodyMedium),
                  const SizedBox(height: SfSpace.md),
                  Row(children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: SfRadius.pillAll,
                        child: LinearProgressIndicator(
                            value: uploadedCount / kRequiredDocs.length,
                            minHeight: 8),
                      ),
                    ),
                    const SizedBox(width: SfSpace.sm),
                    Text('$uploadedCount of ${kRequiredDocs.length}',
                        style: text.labelMedium),
                  ]),
                  if (profile.isPendingReview) ...[
                    const SizedBox(height: SfSpace.md),
                    const InlineMessage(
                        "Your documents are being reviewed. We'll let you know once you're approved.",
                        isError: false),
                  ] else if (profile.isRejected) ...[
                    const SizedBox(height: SfSpace.md),
                    const InlineMessage(
                        'Your application was not approved. Please re-upload clear photos.'),
                  ] else if (allDone) ...[
                    const SizedBox(height: SfSpace.md),
                    const InlineMessage(
                        'All documents are in. Our team will review them shortly.',
                        isError: false),
                  ],
                ]),
              ),
              const Divider(),
              for (final docType in kRequiredDocs) ...[
                Builder(builder: (context) {
                  final isUploaded = _uploaded[docType] == true;
                  final isUploading = _uploading[docType] == true;
                  final isVerified = profile.documents
                          .where((d) => d.docType == docType)
                          .firstOrNull
                          ?.isVerified ??
                      false;
                  final (pill, tone) = isVerified
                      ? ('Verified', PillTone.success)
                      : isUploaded
                          ? ('In review', PillTone.warning)
                          : ('Needed', PillTone.neutral);
                  return ListRow(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: const BoxDecoration(
                          color: SfColors.surface2, shape: BoxShape.circle),
                      child: isUploading
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(
                              isVerified
                                  ? Icons.verified_outlined
                                  : isUploaded
                                      ? Icons.check_rounded
                                      : Icons.photo_camera_outlined,
                              size: 20,
                              color: SfColors.accentStrong),
                    ),
                    title: kDocLabels[docType] ?? docType,
                    trailing: isVerified
                        ? StatusPill(pill, tone: tone)
                        : Row(mainAxisSize: MainAxisSize.min, children: [
                            StatusPill(pill, tone: tone),
                            const SizedBox(width: SfSpace.xs),
                            SfButton.text(
                              label: isUploaded ? 'Replace' : 'Upload',
                              onPressed: isUploading ? null : () => _pick(docType),
                            ),
                          ]),
                  );
                }),
                const Divider(indent: SfSpace.md, endIndent: SfSpace.md),
              ],
            ]),
          );
        },
      ),
    );
  }
}
