import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import '../../auth/auth_service.dart';
import '../../config/app_theme.dart';
import '../../providers/providers.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _pinCtrl = TextEditingController();
  bool _loading  = false;
  String? _error;
  int _secondsLeft = 90;
  Timer? _timer;

  late String _phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _phone = ModalRoute.of(context)!.settings.arguments as String;
    _startTimer();
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _secondsLeft = 90);
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else {
        if (mounted) setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await AuthService.instance.requestOtp(_phone);
      _startTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP resent!')),
      );
    } catch (_) {
      setState(() => _error = 'Failed to resend OTP.');
    }
  }

  Future<void> _verify(String code) async {
    if (code.length < 6) return;
    setState(() { _loading = true; _error = null; });

    try {
      final tokens = await AuthService.instance.verifyOtp(_phone, code);
      ref.read(authProvider.notifier).setUser(tokens.user);
      final destination = await AuthService.instance.postLoginRoute();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed(destination);
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Invalid OTP. Please try again.';
      setState(() { _error = msg; _loading = false; });
      _pinCtrl.clear();
    } catch (_) {
      setState(() { _error = 'Something went wrong.'; _loading = false; });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 54,
      height: 60,
      textStyle: const TextStyle(
          fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.brand),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: AppTheme.brand,
        title: const Text('Verify Phone',
            style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.sms_outlined, size: 64, color: AppTheme.accent),
              const SizedBox(height: 24),
              Text('Enter the 6-digit code',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold, color: AppTheme.brand)),
              const SizedBox(height: 8),
              Text('Sent to $_phone',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.black54)),
              const SizedBox(height: 40),
              // PIN input
              Pinput(
                controller:   _pinCtrl,
                length:       6,
                autofocus:    true,
                defaultPinTheme: pinTheme,
                focusedPinTheme: pinTheme.copyDecorationWith(
                  border: Border.all(color: AppTheme.accent, width: 2),
                ),
                onCompleted: _verify,
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
              if (_loading)
                const CircularProgressIndicator(color: AppTheme.accent)
              else if (_secondsLeft > 0)
                Text('Resend code in ${_secondsLeft}s',
                    style: const TextStyle(color: Colors.black38))
              else
                TextButton(
                  onPressed: _resend,
                  child: const Text("Didn't receive it? Resend",
                      style: TextStyle(
                          color: AppTheme.accent, fontWeight: FontWeight.w600)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
