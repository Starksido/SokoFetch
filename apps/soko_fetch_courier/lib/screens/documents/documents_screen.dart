import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../network/api_client.dart';
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
      backgroundColor: error ? AppTheme.accent : AppTheme.teal,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(courierProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Documents')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error:   (_, __) => const Center(child: Text('Failed to load profile')),
        data:    (profile) {
          // Merge server-side uploads with local state
          for (final doc in profile.documents) {
            _uploaded[doc.docType] = true;
          }

          final uploadedCount = kRequiredDocs.where((d) => _uploaded[d] == true).length;
          final allDone = uploadedCount == kRequiredDocs.length;

          return ListView(padding: const EdgeInsets.all(16), children: [
            // Progress bar
            Card(child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('Upload Progress', style: TextStyle(fontWeight: FontWeight.bold)),
                  Text('$uploadedCount / ${kRequiredDocs.length}',
                      style: const TextStyle(color: AppTheme.accent, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: uploadedCount / kRequiredDocs.length,
                  backgroundColor: AppTheme.lgray,
                  color: AppTheme.accent,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(4),
                ),
                if (allDone) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: AppTheme.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8)),
                    child: const Row(children: [
                      Icon(Icons.check_circle, color: AppTheme.teal, size: 18),
                      SizedBox(width: 8),
                      Expanded(child: Text(
                          'All documents submitted! Our team will review within 24 hours.',
                          style: TextStyle(fontSize: 12))),
                    ]),
                  ),
                ],
              ]),
            )),
            const SizedBox(height: 12),

            // Status banner
            if (profile.isPendingReview)
              _StatusBanner(
                icon: Icons.access_time_outlined,
                color: AppTheme.gold,
                message: 'Your documents are under review. We\'ll notify you once approved.',
              ),
            if (profile.isRejected)
              _StatusBanner(
                icon: Icons.error_outline,
                color: AppTheme.accent,
                message: 'Your application was rejected. Please re-upload correct documents.',
              ),

            const SizedBox(height: 8),

            // Document tiles
            ...kRequiredDocs.map((docType) {
              final isUploaded   = _uploaded[docType]  == true;
              final isUploading  = _uploading[docType] == true;
              final serverDoc    = profile.documents.where((d) => d.docType == docType).firstOrNull;
              final isVerified   = serverDoc?.isVerified ?? false;

              return _DocTile(
                label:       kDocLabels[docType] ?? docType,
                isUploaded:  isUploaded,
                isVerified:  isVerified,
                isUploading: isUploading,
                onTap:       isUploading ? null : () => _pick(docType),
              );
            }),

            const SizedBox(height: 24),
            if (!allDone)
              const Center(child: Text(
                  'Upload all 5 documents to submit for review.',
                  style: TextStyle(color: AppTheme.mgray, fontSize: 13),
                  textAlign: TextAlign.center)),
          ]);
        },
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final String label;
  final bool isUploaded, isVerified, isUploading;
  final VoidCallback? onTap;
  const _DocTile({
    required this.label, required this.isUploaded,
    required this.isVerified, required this.isUploading, this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color borderColor = isVerified ? AppTheme.teal
        : isUploaded ? AppTheme.gold
        : Colors.grey.shade200;
    Color iconColor = isVerified ? AppTheme.teal
        : isUploaded ? AppTheme.gold
        : AppTheme.mgray;
    IconData icon = isVerified ? Icons.verified_outlined
        : isUploaded ? Icons.check_circle_outline
        : Icons.upload_file_outlined;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: borderColor, width: 1.5)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1), shape: BoxShape.circle),
          child: isUploading
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.accent))
              : Icon(icon, color: iconColor),
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          isVerified ? 'Verified ✓'
              : isUploaded ? 'Uploaded — pending review'
              : 'Tap to upload',
          style: TextStyle(fontSize: 11, color: iconColor),
        ),
        trailing: !isVerified
            ? ElevatedButton(
                onPressed: onTap,
                style: ElevatedButton.styleFrom(
                    backgroundColor: isUploaded ? AppTheme.mgray : AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                child: Text(isUploaded ? 'Replace' : 'Upload',
                    style: const TextStyle(fontSize: 12)),
              )
            : null,
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _StatusBanner({required this.icon, required this.color, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3))),
    child: Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: TextStyle(color: color, fontSize: 12))),
    ]),
  );
}
