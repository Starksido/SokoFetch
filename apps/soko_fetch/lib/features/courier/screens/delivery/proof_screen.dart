import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pinput/pinput.dart';

import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';
import '../../providers/providers.dart';

/// POST /orders/{id}/proof is a multipart form: `otp_code` (the customer's
/// 4-digit delivery code, always required) plus an optional `photo`.
class ProofOfDeliveryScreen extends ConsumerStatefulWidget {
  const ProofOfDeliveryScreen({super.key});
  @override
  ConsumerState<ProofOfDeliveryScreen> createState() => _ProofScreenState();
}

class _ProofScreenState extends ConsumerState<ProofOfDeliveryScreen> {
  final _codeCtrl = TextEditingController();
  bool _submitting = false;
  String? _photoPath;
  String? _error;
  late Order _order;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _order = ModalRoute.of(context)!.settings.arguments as Order;
  }

  @override
  void dispose() { _codeCtrl.dispose(); super.dispose(); }

  Future<void> _pickPhoto() async {
    final result = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1280, maxHeight: 1280, imageQuality: 80,
    );
    if (result != null && mounted) setState(() => _photoPath = result.path);
  }

  Future<void> _submit() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 4) {
      setState(() => _error = 'Enter the 4-digit delivery code from the customer.');
      return;
    }
    setState(() { _submitting = true; _error = null; });
    try {
      final form = FormData.fromMap({
        'otp_code': code,
        if (_photoPath != null)
          'photo': await MultipartFile.fromFile(_photoPath!, filename: 'proof.jpg'),
      });
      await ApiClient.instance.dio.post(
        '/orders/${_order.id}/proof',
        data: form,
        options: Options(contentType: 'multipart/form-data'),
      );

      ref.invalidate(activeOrderProvider);
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/courier', (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Delivery confirmed. Nice work!')),
      );
    } on DioException catch (e) {
      if (mounted) setState(() => _error = _messageFrom(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Wrong code (400) and lockout (429) carry {"detail": {"message": ...}}.
  String _messageFrom(DioException e) {
    final data = e.response?.data;
    final detail = data is Map ? data['detail'] : null;
    if (detail is Map && detail['message'] is String) return detail['message'] as String;
    if (e.response == null) return 'Submission failed. Check your connection and try again.';
    return 'Could not confirm delivery. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final pinTheme = PinTheme(
      width: 56,
      height: 64,
      textStyle: text.headlineMedium,
      decoration: const BoxDecoration(
          color: SfColors.surface2, borderRadius: SfRadius.mdAll),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm delivery')),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(SfSpace.md, SfSpace.xs, SfSpace.md, 0),
            child: InlineMessage(_error!),
          ),
        BottomCtaBar(
            label: 'Confirm Delivery', loading: _submitting, onPressed: _submit),
      ]),
      body: MaxWidth(
        maxWidth: 520,
        child: ListView(
          padding: const EdgeInsets.all(SfSpace.md),
          children: [
            ListRow(
              leading: const Icon(Icons.place_outlined),
              title: _order.deliveryAddress,
              subtitle: 'You earn ${formatKes(_order.courierPayout)}',
            ),
            const SizedBox(height: SfSpace.lg),
            Text('Delivery code', style: text.titleLarge),
            const SizedBox(height: SfSpace.xxs),
            Text('Ask the customer for the 4-digit code in their app.',
                style: text.bodyMedium),
            const SizedBox(height: SfSpace.md),
            Center(
              child: Pinput(
                controller: _codeCtrl,
                length: 4,
                autofocus: true,
                defaultPinTheme: pinTheme,
                focusedPinTheme: pinTheme.copyDecorationWith(
                  color: SfColors.surface,
                  border: Border.all(color: SfColors.brand, width: 2),
                ),
              ),
            ),
            const SizedBox(height: SfSpace.xl),
            Text('Photo (optional)', style: text.titleLarge),
            const SizedBox(height: SfSpace.sm),
            InkWell(
              onTap: _pickPhoto,
              borderRadius: SfRadius.mdAll,
              child: Container(
                height: 180,
                decoration: const BoxDecoration(
                    color: SfColors.surface2, borderRadius: SfRadius.mdAll),
                child: _photoPath != null
                    ? ClipRRect(
                        borderRadius: SfRadius.mdAll,
                        child: Image.file(File(_photoPath!),
                            fit: BoxFit.cover,
                            width: double.infinity,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.check_circle,
                                    color: SfColors.success, size: 48))))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.photo_camera_outlined,
                              size: 36, color: SfColors.accentStrong),
                          const SizedBox(height: SfSpace.xs),
                          Text('Take a photo of the handover',
                              style: text.bodyMedium),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
