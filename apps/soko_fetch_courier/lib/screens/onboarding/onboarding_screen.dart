import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../network/api_client.dart';
import '../../providers/providers.dart';

/// Shown after login when the account has no courier profile yet
/// (GET /courier/me → 404). Creates it via POST /courier/onboard; the courier
/// then uploads documents and waits for review before going online.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  // Must match VehicleType on the backend
  static const _vehicles = {
    'motorcycle': 'Motorcycle',
    'bicycle':    'Bicycle',
    'on_foot':    'On foot',
  };

  final _formKey  = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _plate    = TextEditingController();
  String _vehicle = 'motorcycle';
  bool _saving    = false;
  String? _error;

  @override
  void dispose() {
    _fullName.dispose();
    _plate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      await ApiClient.instance.post('/courier/onboard', data: {
        'full_name':    _fullName.text.trim(),
        'vehicle_type': _vehicle,
        if (_vehicle == 'motorcycle' && _plate.text.trim().isNotEmpty)
          'vehicle_plate': _plate.text.trim().toUpperCase(),
      });
      ref.invalidate(courierProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Profile created. Next, upload your documents.'),
      ));
      Navigator.pushReplacementNamed(context, '/home');
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
    return 'Could not create your profile. Please try again.';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Become a rider')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Tell us about yourself. After this you will upload your '
                'documents for review.',
                style: TextStyle(color: AppTheme.mgray),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _fullName,
                decoration: const InputDecoration(labelText: 'Full name (as on your ID)'),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().length < 2)
                    ? 'Enter your full name' : null,
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _vehicle,
                decoration: const InputDecoration(labelText: 'How will you deliver?'),
                items: [
                  for (final e in _vehicles.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => setState(() => _vehicle = v ?? _vehicle),
              ),
              if (_vehicle == 'motorcycle') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: _plate,
                  decoration: const InputDecoration(labelText: 'Number plate'),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Enter your number plate'
                      : (v.trim().length > 20 ? 'Too long' : null),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: AppTheme.accent)),
              ],
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
