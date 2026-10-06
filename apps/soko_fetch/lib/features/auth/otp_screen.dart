import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../core/errors.dart';
import '../../core/theme.dart';
import 'auth_service.dart';
import 'continue_after_auth.dart';
import 'welcome_screen.dart' show ErrorBanner;

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _pinCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  int _secondsLeft = 90;
  Timer? _timer;
  String? _phone;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_phone == null) {
      _phone = ModalRoute.of(context)!.settings.arguments as String;
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _secondsLeft = 90;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_secondsLeft <= 0) {
        t.cancel();
      } else if (mounted) {
        setState(() => _secondsLeft--);
      }
    });
  }

  Future<void> _resend() async {
    setState(() => _error = null);
    try {
      await AuthService.instance.requestOtp(_phone!);
      if (!mounted) return;
      setState(_startTimer);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('OTP resent!')));
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, 'Failed to resend OTP.'));
    }
  }

  Future<void> _verify(String code) async {
    if (code.length < 6 || _loading) return;
    setState(() { _loading = true; _error = null; });
    try {
      final result = await AuthService.instance.verifyOtp(_phone!, code);
      if (!mounted) return;
      await continueAfterAuth(context, ref, result);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = errorMessage(e, 'Invalid OTP. Please try again.');
        _loading = false;
      });
      _pinCtrl.clear();
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
        foregroundColor: AppTheme.brand,
        title: const Text('Verify Phone',
            style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: AppTheme.brand)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.sms_outlined, size: 64, color: AppTheme.accent),
              const SizedBox(height: 24),
              const Text('Enter the 6-digit code',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.brand)),
              const SizedBox(height: 8),
              Text('Sent to $_phone',
                  style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 40),
              Pinput(
                controller: _pinCtrl,
                length: 6,
                autofocus: true,
                defaultPinTheme: pinTheme,
                focusedPinTheme: pinTheme.copyDecorationWith(
                  border: Border.all(color: AppTheme.accent, width: 2),
                ),
                onCompleted: _verify,
              ),
              if (_error != null) ...[
                const SizedBox(height: 16),
                ErrorBanner(_error!),
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
