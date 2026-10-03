import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../network/api_client.dart';

class ProofOfDeliveryScreen extends StatefulWidget {
  const ProofOfDeliveryScreen({super.key});
  @override
  State<ProofOfDeliveryScreen> createState() => _ProofScreenState();
}

class _ProofScreenState extends State<ProofOfDeliveryScreen> {
  String _mode = 'photo';   // 'photo' | 'otp'
  final _otpCtrl = TextEditingController();
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
  void dispose() { _otpCtrl.dispose(); super.dispose(); }

  Future<void> _pickPhoto() async {
    final result = await ImagePicker().pickImage(
      source: ImageSource.camera,
      maxWidth: 1280, maxHeight: 1280, imageQuality: 80,
    );
    if (result != null) setState(() => _photoPath = result.path);
  }

  Future<void> _submit() async {
    setState(() { _submitting = true; _error = null; });
    try {
      if (_mode == 'photo') {
        if (_photoPath == null) {
          setState(() { _error = 'Please take a photo first.'; _submitting = false; });
          return;
        }
        final form = FormData.fromMap({
          'file': await MultipartFile.fromFile(_photoPath!, filename: 'proof.jpg'),
        });
        await ApiClient.instance.dio.post(
          '/orders/${_order.id}/proof?proof_type=photo',
          data: form,
          options: Options(contentType: 'multipart/form-data'),
        );
      } else {
        final code = _otpCtrl.text.trim();
        if (code.length < 4) {
          setState(() { _error = 'Enter the OTP from the customer.'; _submitting = false; });
          return;
        }
        await ApiClient.instance.post('/orders/${_order.id}/proof', data: {
          'proof_type': 'otp',
          'otp_code':   code,
        });
      }

      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Delivery confirmed! 🎉'),
          backgroundColor: AppTheme.teal,
        ),
      );
    } catch (e) {
      setState(() {
        _error = 'Submission failed. Check your connection and try again.';
        _submitting = false;
      });
    }
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

          // Mode selector
          const Text('Proof Method',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _ModeButton(
              label: 'Photo', icon: Icons.camera_alt_outlined,
              selected: _mode == 'photo',
              onTap: () => setState(() => _mode = 'photo'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _ModeButton(
              label: 'OTP Code', icon: Icons.pin_outlined,
              selected: _mode == 'otp',
              onTap: () => setState(() => _mode = 'otp'),
            )),
          ]),
          const SizedBox(height: 24),

          // Photo mode
          if (_mode == 'photo') ...[
            GestureDetector(
              onTap: _pickPhoto,
              child: Container(
                height: 200,
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
                        child: Image.asset(_photoPath!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.check_circle,
                                    color: AppTheme.teal, size: 48))))
                    : const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.camera_alt_outlined,
                              size: 48, color: AppTheme.mgray),
                          SizedBox(height: 8),
                          Text('Tap to take delivery photo',
                              style: TextStyle(color: AppTheme.mgray)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
                'Take a clear photo showing the delivered items at the customer\'s door.',
                style: TextStyle(color: AppTheme.mgray, fontSize: 12),
                textAlign: TextAlign.center),
          ],

          // OTP mode
          if (_mode == 'otp') ...[
            const Text(
                'Ask the customer for their 4-digit delivery code and enter it below.',
                style: TextStyle(color: AppTheme.mgray, fontSize: 13)),
            const SizedBox(height: 16),
            TextField(
              controller: _otpCtrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
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
          ],

          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
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

class _ModeButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton(
      {required this.label, required this.icon,
      required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppTheme.accent.withOpacity(0.08) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: selected ? AppTheme.accent : Colors.grey.shade200,
            width: selected ? 2 : 1),
      ),
      child: Column(children: [
        Icon(icon, color: selected ? AppTheme.accent : AppTheme.mgray),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: selected ? AppTheme.accent : AppTheme.mgray,
                fontSize: 13)),
      ]),
    ),
  );
}
