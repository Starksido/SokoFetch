import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../../core/errors.dart';
import '../../core/ui/ui.dart';
import 'auth_service.dart';
import 'continue_after_auth.dart';

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
    final text = Theme.of(context).textTheme;
    final pinTheme = PinTheme(
      width: 48,
      height: 56,
      textStyle: text.headlineSmall,
      decoration: const BoxDecoration(
        color: SfColors.surface2,
        borderRadius: SfRadius.mdAll,
      ),
    );

    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 480,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                SfSpace.lg, SfSpace.xs, SfSpace.lg, SfSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Enter the 6-digit code', style: text.headlineMedium),
                const SizedBox(height: SfSpace.xs),
                Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'We sent it to '),
                    TextSpan(
                        text: _phone,
                        style: const TextStyle(
                            color: SfColors.ink, fontWeight: FontWeight.w600)),
                  ]),
                  style: text.bodyLarge!.copyWith(color: SfColors.inkMuted),
                ),
                const SizedBox(height: SfSpace.xl),
                Center(
                  child: Pinput(
                    controller: _pinCtrl,
                    length: 6,
                    autofocus: true,
                    defaultPinTheme: pinTheme,
                    focusedPinTheme: pinTheme.copyDecorationWith(
                      color: SfColors.surface,
                      border: Border.all(color: SfColors.ink, width: 2),
                    ),
                    errorPinTheme: pinTheme.copyDecorationWith(
                      border: Border.all(color: SfColors.danger, width: 2),
                    ),
                    forceErrorState: _error != null,
                    onCompleted: _verify,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: SfSpace.md),
                  InlineMessage(_error!),
                ],
                const SizedBox(height: SfSpace.lg),
                if (_loading)
                  const SfLoader()
                else if (_secondsLeft > 0)
                  Text('Resend code in ${_secondsLeft}s', style: text.bodyMedium)
                else
                  SfButton.secondary(
                    label: "Didn't get it? Resend code",
                    expand: false,
                    onPressed: _resend,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
