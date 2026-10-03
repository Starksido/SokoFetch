import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../../auth/auth_service.dart';
import '../../auth/google_signin_service.dart';
import '../../config/app_theme.dart';

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
      await AuthService.instance.onboardCustomer(
        fullName: _nameCtrl.text.trim(),
        email: _emailCtrl.text.trim(),
      );

      if (_googleVerified && _googleIdToken != null) {
        try {
          await AuthService.instance.verifyGoogleAccount(_googleIdToken!);
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 48),
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.person_outline,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(height: 36),
                Text('Tell us about you',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brand,
                        )),
                const SizedBox(height: 8),
                Text("Just a couple of details to finish setting up your account.",
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        )),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Full name',
                    hintText: 'Jane Wanjiru',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppTheme.accent, width: 2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) {
                      return 'Enter your full name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email address',
                    hintText: 'jane@example.com',
                    prefixIcon: const Icon(Icons.email_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppTheme.accent, width: 2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Enter your email address';
                    }
                    final emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
                    if (!emailPattern.hasMatch(v.trim())) {
                      return 'Enter a valid email address';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _googleLoading ? null : _verifyWithGoogle,
                  icon: _googleLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        )
                      : Icon(
                          _googleVerified
                              ? Icons.check_circle
                              : Icons.g_mobiledata,
                          color: _googleVerified
                              ? Colors.green
                              : AppTheme.brand,
                        ),
                  label: Text(
                    _googleVerified
                        ? 'Google account verified'
                        : 'Verify with Google',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    side: BorderSide(
                      color: _googleVerified
                          ? Colors.green
                          : Colors.grey.shade300,
                    ),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline,
                          color: AppTheme.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(_error!,
                            style: const TextStyle(color: AppTheme.accent)),
                      ),
                    ]),
                  ),
                ],
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      elevation: 0,
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Text('Continue',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }
}