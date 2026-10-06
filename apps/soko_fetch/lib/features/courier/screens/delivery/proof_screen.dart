import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/theme.dart';
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
        const SnackBar(
          content: Text('Delivery confirmed! 🎉'),
          backgroundColor: AppTheme.teal,
        ),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Delivery')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Order summary
          Card(child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Order Summary',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 8),
              Text(_order.deliveryAddress,
                  style: const TextStyle(color: AppTheme.mgray, fontSize: 13)),
              const SizedBox(height: 4),
              Text('Payout: KES ${_order.courierPayout.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppTheme.teal, fontWeight: FontWeight.bold)),
            ]),
          )),
          const SizedBox(height: 20),

          // Delivery code (required)
          const Text('Delivery Code',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 6),
          const Text(
              'Ask the customer for the 4-digit code shown in their app.',
              style: TextStyle(color: AppTheme.mgray, fontSize: 13)),
          const SizedBox(height: 12),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 4,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.bold,
                letterSpacing: 12),
            decoration: const InputDecoration(
              hintText: '• • • •',
              counterText: '',
              hintStyle: TextStyle(letterSpacing: 12, color: AppTheme.mgray),
            ),
          ),
          const SizedBox(height: 24),

          // Photo (optional)
          const Text('Photo (optional)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: _pickPhoto,
            child: Container(
              height: 160,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: _photoPath != null
                        ? AppTheme.teal
                        : Colors.grey.shade200,
                    width: 2),
              ),
              child: _photoPath != null
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(13),
                      child: Image.file(File(_photoPath!), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.check_circle,
                                  color: AppTheme.teal, size: 48))))
                  : const Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.camera_alt_outlined,
                            size: 40, color: AppTheme.mgray),
                        SizedBox(height: 8),
                        Text('Tap to add a delivery photo',
                            style: TextStyle(color: AppTheme.mgray)),
                      ],
                    ),
            ),
          ),

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_error!,
                  style: const TextStyle(color: AppTheme.accent, fontSize: 13)),
            ),
          ],

          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _submitting ? null : _submit,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54),
                backgroundColor: AppTheme.teal),
            child: _submitting
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Confirm Delivery',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
    );
  }
}
