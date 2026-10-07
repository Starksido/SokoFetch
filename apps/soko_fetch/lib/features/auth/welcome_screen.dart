import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/google_sign_in.dart';
import '../../core/ui/ui.dart';
import 'auth_service.dart';
import 'continue_after_auth.dart';

/// Sign in or sign up: the same screen for everyone. New users pick
/// customer, merchant or courier after verifying their phone or Google account.
class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  String? _error;

  String get _normalised {
    String p = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (p.startsWith('0')) p = '+254${p.substring(1)}';
    if (!p.startsWith('+')) p = '+254$p';
    return p;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _loading = true; _error = null; });
    try {
      await AuthService.instance.requestOtp(_normalised);
      if (!mounted) return;
      Navigator.of(context).pushNamed('/auth/otp', arguments: _normalised);
    } catch (e) {
      setState(() => _error = errorMessage(e, 'Failed to send the code. Please try again.'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _error = null; });
    try {
      final google = await GoogleSignInService.instance.signIn();
      if (google == null) return; // Cancelled
      final result = await AuthService.instance.signInWithGoogle(google.idToken);
      if (!mounted) return;
      await continueAfterAuth(context, ref, result);
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e, 'Google sign-in failed. Please try again.'));
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final busy = _loading || _googleLoading;
    return Scaffold(
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                SfSpace.lg, SfSpace.xl, SfSpace.lg, SfSpace.lg),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(children: [
                    SokoMark(size: 40),
                    SizedBox(width: SfSpace.sm),
                    Flexible(child: SokoWordmark()),
                  ]),
                  const SizedBox(height: SfSpace.xxl),
                  Text('Your local shops,\ndelivered.', style: text.headlineMedium),
                  const SizedBox(height: SfSpace.xs),
                  Text('Sign in or create an account with your phone number.',
                      style: text.bodyLarge!.copyWith(color: SfColors.inkMuted)),
                  const SizedBox(height: SfSpace.xl),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.go,
                    onFieldSubmitted: (_) => busy ? null : _submit(),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
                    ],
                    style: text.bodyLarge,
                    decoration: InputDecoration(
                      hintText: '0712 345 678',
                      prefixIcon: Padding(
                        padding: const EdgeInsets.only(
                            left: SfSpace.md, right: SfSpace.xs),
                        child: Text('🇰🇪  +254',
                            style: text.bodyLarge!
                                .copyWith(fontWeight: FontWeight.w600)),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'Enter your phone number';
                      final p = v.trim().replaceAll(RegExp(r'[\s\-]'), '');
                      if (p.length < 9) return 'Phone number is too short';
                      return null;
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: SfSpace.sm),
                    InlineMessage(_error!),
                  ],
                  const SizedBox(height: SfSpace.md),
                  SfButton.primary(
                    label: 'Continue',
                    loading: _loading,
                    onPressed: busy ? null : _submit,
                  ),
                  const SizedBox(height: SfSpace.lg),
                  Row(children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: SfSpace.sm),
                      child: Text('or', style: text.bodyMedium),
                    ),
                    const Expanded(child: Divider()),
                  ]),
                  const SizedBox(height: SfSpace.lg),
                  SfButton.secondary(
                    label: 'Continue with Google',
                    icon: Icons.g_mobiledata_rounded,
                    loading: _googleLoading,
                    onPressed: busy ? null : _signInWithGoogle,
                  ),
                  const SizedBox(height: SfSpace.lg),
                  Text(
                    "We'll text you a 6-digit code. Standard SMS rates may apply.",
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
