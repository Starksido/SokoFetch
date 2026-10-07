import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../core/ui/ui.dart';
import '../../../../core/api_client.dart';

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
      Navigator.pushReplacementNamed(context, '/merchant');
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      bottomNavigationBar: BottomCtaBar(
          label: 'Create shop', loading: _saving, onPressed: _submit),
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 560,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                  SfSpace.lg, SfSpace.xl, SfSpace.lg, SfSpace.lg),
              children: [
                Text('Set up your shop', style: text.headlineMedium),
                const SizedBox(height: SfSpace.xs),
                Text(
                  'Tell customers about your shop. You can change these details later.',
                  style: text.bodyLarge!.copyWith(color: SfColors.inkMuted),
                ),
                const SizedBox(height: SfSpace.xl),
                TextFormField(
                  controller: _shopName,
                  decoration: const InputDecoration(
                    labelText: 'Shop name',
                    prefixIcon: Icon(Icons.storefront_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().length < 2)
                      ? 'Enter your shop name'
                      : null,
                ),
                const SizedBox(height: SfSpace.lg),
                Text('What do you sell?', style: text.titleSmall),
                const SizedBox(height: SfSpace.xs),
                Wrap(spacing: SfSpace.xs, runSpacing: SfSpace.xs, children: [
                  for (final e in _categories.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: _category == e.key,
                      onSelected: (_) => setState(() => _category = e.key),
                    ),
                ]),
                const SizedBox(height: SfSpace.lg),
                TextFormField(
                  controller: _address,
                  decoration: const InputDecoration(
                    labelText: 'Shop address',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  validator: (v) => (v == null || v.trim().length < 5)
                      ? 'Enter the full address'
                      : null,
                ),
                const SizedBox(height: SfSpace.sm),
                TextFormField(
                  controller: _city,
                  decoration: const InputDecoration(
                    labelText: 'City',
                    prefixIcon: Icon(Icons.location_city_outlined),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Enter a city' : null,
                ),
                const SizedBox(height: SfSpace.sm),
                TextFormField(
                  controller: _description,
                  decoration:
                      const InputDecoration(labelText: 'Description (optional)'),
                  maxLines: 3,
                  minLines: 2,
                ),
                const SizedBox(height: SfSpace.sm),
                TextFormField(
                  controller: _payoutPhone,
                  decoration: const InputDecoration(
                    labelText: 'M-Pesa number for payouts (optional)',
                    prefixIcon: Icon(Icons.phone_iphone_rounded),
                  ),
                  keyboardType: TextInputType.phone,
                ),
                if (_error != null) ...[
                  const SizedBox(height: SfSpace.md),
                  InlineMessage(_error!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
