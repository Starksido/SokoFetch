import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';
import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../network/api_client.dart';
import '../../providers/providers.dart';

// ══════════════════════════════════════════════════════════════════════════════
// Phone Screen
// ══════════════════════════════════════════════════════════════════════════════
class PhoneScreen extends StatefulWidget {
  const PhoneScreen({super.key});
  @override
  State<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends State<PhoneScreen> {
  final _ctrl    = TextEditingController();
  bool  _loading = false;
  String? _error;

  String get _phone {
    String p = _ctrl.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (p.startsWith('0')) p = '+254${p.substring(1)}';
    if (!p.startsWith('+')) p = '+254$p';
    return p;
  }

  Future<void> _submit() async {
    setState(() { _loading = true; _error = null; });
    try {
      await ApiClient.instance.post('/auth/otp/request',
          data: {'phone': _phone, 'role': 'merchant'});
      if (!mounted) return;
      Navigator.pushNamed(context, '/auth/otp', arguments: _phone);
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Failed to send OTP.';
      setState(() => _error = msg);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppTheme.brand,
    body: SafeArea(
      child: Column(children: [
        const SizedBox(height: 60),
        const Icon(Icons.storefront_outlined,
            color: Colors.white, size: 64),
        const SizedBox(height: 16),
        const Text('Merchant Portal',
            style: TextStyle(color: Colors.white,
                fontSize: 26, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text('Sign in to manage your shop',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
        const SizedBox(height: 48),
        Expanded(
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Phone number',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _ctrl,
                  keyboardType: TextInputType.phone,
                  autofocus: true,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
                  ],
                  decoration: const InputDecoration(
                    hintText: '0712 345 678',
                    prefixIcon: Icon(Icons.phone_outlined),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(_error!,
                      style: const TextStyle(color: AppTheme.red, fontSize: 12)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                  child: _loading
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Text('Get OTP'),
                ),
              ],
            ),
          ),
        ),
      ]),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// OTP Screen
// ══════════════════════════════════════════════════════════════════════════════
class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({super.key});
  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  final _ctrl    = TextEditingController();
  bool  _loading = false;
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
      if (_secondsLeft <= 0) { t.cancel(); return; }
      if (mounted) setState(() => _secondsLeft--);
    });
  }

  Future<void> _verify(String code) async {
    if (code.length < 6) return;
    setState(() { _loading = true; _error = null; });
    try {
      final resp = await ApiClient.instance.post('/auth/otp/verify',
          data: {'phone': _phone, 'otp_code': code, 'role': 'merchant'});
      final tokens = AuthTokens.fromJson(resp.data as Map<String, dynamic>);
      await ApiClient.saveTokens(
        access:  tokens.accessToken,
        refresh: tokens.refreshToken,
        userId:  tokens.user.userId,
        role:    tokens.user.role,
      );
      ref.read(authProvider.notifier).setUser(tokens.user);
      final destination = await ApiClient.instance.postLoginRoute();
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, destination);
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Invalid OTP.';
      setState(() { _error = msg; _loading = false; });
      _ctrl.clear();
    } catch (_) {
      setState(() { _error = 'Something went wrong.'; _loading = false; });
    }
  }

  @override
  void dispose() { _timer?.cancel(); _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 52, height: 58,
      textStyle: const TextStyle(
          fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.brand),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(12),
      ),
    );

    return Scaffold(
      appBar: AppBar(
          title: const Text('Verify Phone'),
          backgroundColor: Colors.white,
          foregroundColor: AppTheme.brand),
      backgroundColor: Colors.white,
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(children: [
          const SizedBox(height: 24),
          const Icon(Icons.sms_outlined, size: 56, color: AppTheme.accent),
          const SizedBox(height: 16),
          Text('Code sent to $_phone',
              style: const TextStyle(color: AppTheme.mgray)),
          const SizedBox(height: 32),
          Pinput(
            controller: _ctrl,
            length: 6,
            autofocus: true,
            defaultPinTheme: pinTheme,
            focusedPinTheme: pinTheme.copyDecorationWith(
                border: Border.all(color: AppTheme.accent, width: 2)),
            onCompleted: _verify,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!,
                style: const TextStyle(color: AppTheme.red, fontSize: 12)),
          ],
          const SizedBox(height: 28),
          if (_loading)
            const CircularProgressIndicator(color: AppTheme.accent)
          else if (_secondsLeft > 0)
            Text('Resend in ${_secondsLeft}s',
                style: const TextStyle(color: AppTheme.mgray))
          else
            TextButton(
              onPressed: () async {
                await ApiClient.instance.post('/auth/otp/request',
                    data: {'phone': _phone, 'role': 'merchant'});
                _startTimer();
              },
              child: const Text('Resend OTP',
                  style: TextStyle(color: AppTheme.accent)),
            ),
        ]),
      ),
    );
  }
}
