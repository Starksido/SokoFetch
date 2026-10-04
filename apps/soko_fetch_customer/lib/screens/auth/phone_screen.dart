import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../auth/auth_service.dart';
import '../../config/app_theme.dart';
import '../../auth/google_signin_service.dart';

class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});

  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _formKey = GlobalKey<FormState>();
  final _phoneCtrl = TextEditingController();
  bool _loading = false;
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
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Failed to send OTP. Please try again.';
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await GoogleSignInService.instance.signIn();
      if (result == null) {
        setState(() => _loading = false);
        return; // user cancelled
      }
      await AuthService.instance.signInWithGoogle(result.idToken);
      final destination = await AuthService.instance.postLoginRoute();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(destination);
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Google sign-in failed. Please try again.';
      setState(() => _error = msg);
    } catch (_) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 64),
                // Back / logo
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(Icons.delivery_dining,
                      color: Colors.white, size: 30),
                ),
                const SizedBox(height: 36),
                Text('Welcome to Soko Fetch',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.brand,
                        )),
                const SizedBox(height: 8),
                Text('Enter your phone number to get started.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.black54,
                        )),
                const SizedBox(height: 40),
                // Phone field
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))],
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Phone number',
                    hintText: '0712 345 678',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide:
                          const BorderSide(color: AppTheme.accent, width: 2),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter your phone number';
                    final p = v.trim().replaceAll(RegExp(r'[\s\-]'), '');
                    if (p.length < 9) return 'Phone number is too short';
                    return null;
                  },
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
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
                        : const Text('Get OTP',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 16),
                Row(children: const [
                  Expanded(child: Divider()),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or', style: TextStyle(color: Colors.black38)),
                  ),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _signInWithGoogle,
                    icon: const Icon(Icons.g_mobiledata, size: 28),
                    label: const Text('Continue with Google',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.black26),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Center(
                  child: Text(
                    "We'll send a 6-digit code to your phone.\nStandard SMS rates may apply.",
                    textAlign: TextAlign.center,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black38),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
