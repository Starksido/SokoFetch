import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../network/api_client.dart';

/// Shown after login when the account has no shop yet (GET /merchant/me → 404).
/// Creates the shop via POST /merchant/onboard; it starts in pending review.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  // Must match MerchantCategory on the backend
  static const _categories = {
    'restaurant': 'Restaurant',
    'fast_food':  'Fast food',
    'grocery':    'Grocery',
    'bakery':     'Bakery',
    'beverages':  'Beverages',
    'pharmacy':   'Pharmacy',
    'general':    'General store',
  };

  final _formKey     = GlobalKey<FormState>();
  final _shopName    = TextEditingController();
  final _description = TextEditingController();
  final _address     = TextEditingController();
  final _city        = TextEditingController(text: 'Nairobi');
  final _payoutPhone = TextEditingController();
  String _category   = 'restaurant';
  bool _saving       = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_shopName, _description, _address, _city, _payoutPhone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiClient.instance.post('/merchant/onboard', data: {
        'shop_name': _shopName.text.trim(),
        'category':  _category,
        'address':   _address.text.trim(),
        'city':      _city.text.trim(),
        if (_description.text.trim().isNotEmpty) 'description': _description.text.trim(),
        if (_payoutPhone.text.trim().isNotEmpty) 'payout_phone': _payoutPhone.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Shop created. It will go live once it has been reviewed.'),
      ));
      Navigator.pushReplacementNamed(context, '/dashboard');
    } on DioException catch (e) {
      if (mounted) setState(() => _error = _messageFrom(e));
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// FastAPI errors: {"detail": {"message": ...}} for app errors,
  /// {"detail": [...]} for validation errors.
  String _messageFrom(DioException e) {
    final detail = (e.response?.data is Map) ? (e.response!.data as Map)['detail'] : null;
    if (detail is Map && detail['message'] is String) return detail['message'] as String;
    if (detail is List) return 'Please check the details and try again.';
    return 'Could not create your shop. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Set up your shop')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Tell customers about your shop. You can change these details later.',
                style: TextStyle(color: AppTheme.mgray),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _shopName,
                decoration: const InputDecoration(labelText: 'Shop name'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter your shop name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: [
                  for (final e in _categories.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _category = v ?? _category),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(labelText: 'Shop address'),
                validator: (v) => (v == null || v.trim().length < 5)
                    ? 'Enter the full address' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'City'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a city' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description (optional)'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _payoutPhone,
                decoration: const InputDecoration(
                    labelText: 'M-Pesa payout number (optional)'),
                keyboardType: TextInputType.phone,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.red)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create shop'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
