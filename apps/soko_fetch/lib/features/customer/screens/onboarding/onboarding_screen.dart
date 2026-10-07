import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../../../core/api_client.dart';
import '../../../../core/google_sign_in.dart';
import '../../../../core/ui/ui.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  bool _loading = false;
  bool _googleLoading = false;
  bool _googleVerified = false;
  String? _googleIdToken;
  String? _error;

  Future<void> _verifyWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      final result = await GoogleSignInService.instance.signIn();
      if (result == null) {
        setState(() => _googleLoading = false);
        return;
      }

      if (_nameCtrl.text.trim().isEmpty && result.displayName != null) {
        _nameCtrl.text = result.displayName!;
      }
      if (_emailCtrl.text.trim().isEmpty && result.email != null) {
        _emailCtrl.text = result.email!;
      }

      setState(() {
        _googleVerified = true;
        _googleIdToken = result.idToken;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google account ready to verify.')),
        );
      }
    } catch (_) {
      setState(() => _error = 'Could not connect to Google. Please try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });

    try {
      await ApiClient.instance.post('/customer/onboard', data: {
        'full_name': _nameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
      });

      if (_googleVerified && _googleIdToken != null) {
        try {
          await ApiClient.instance.post('/customer/verify-google',
              data: {'id_token': _googleIdToken!});
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/customer');
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Could not save your details. Please try again.';
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      bottomNavigationBar: BottomCtaBar(
          label: 'Continue', loading: _loading, onPressed: _submit),
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 520,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                SfSpace.lg, SfSpace.xl, SfSpace.lg, SfSpace.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tell us about you', style: text.headlineMedium),
                  const SizedBox(height: SfSpace.xs),
                  Text('Riders and shops use your name for your orders.',
                      style: text.bodyLarge!.copyWith(color: SfColors.inkMuted)),
                  const SizedBox(height: SfSpace.xl),
                  TextFormField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Full name',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                    ),
                    validator: (v) => (v == null || v.trim().length < 2)
                        ? 'Enter your full name'
                        : null,
                  ),
                  const SizedBox(height: SfSpace.sm),
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) {
                        return 'Enter your email address';
                      }
                      final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                      return emailPattern.hasMatch(v.trim())
                          ? null
                          : 'Enter a valid email address';
                    },
                  ),
                  const SizedBox(height: SfSpace.lg),
                  _googleVerified
                      ? const StatusPill('Google account linked',
                          tone: PillTone.success, icon: Icons.check_rounded)
                      : SfButton.secondary(
                          label: 'Fill in with Google',
                          icon: Icons.g_mobiledata_rounded,
                          loading: _googleLoading,
                          onPressed: _verifyWithGoogle,
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
      ),
    );
  }
}
