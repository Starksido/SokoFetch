import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/errors.dart';
import '../../core/session.dart';
import '../../core/ui/ui.dart';

/// Admin login: phone number, then the code sent by SMS. Only admin
/// accounts receive a code; there is no sign-up here.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  bool _codeSent = false;
  bool _loading = false;
  String? _error;

  String get _phone {
    var p = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (p.startsWith('0')) p = '+254${p.substring(1)}';
    if (!p.startsWith('+')) p = '+254$p';
    return p;
  }

  Future<void> _run(Future<void> Function() action, String fallback) async {
    setState(() { _loading = true; _error = null; });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = errorMessage(e, fallback));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendCode() async {
    if (_phoneCtrl.text.trim().length < 9) {
      setState(() => _error = 'Enter your phone number.');
      return;
    }
    await _run(() async {
      await Session.requestCode(_phone);
      if (mounted) setState(() => _codeSent = true);
    }, 'Could not send a code. Please try again.');
  }

  Future<void> _logIn() async {
    final code = _codeCtrl.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code.');
      return;
    }
    // On success the session restarts and the panel replaces this screen
    await _run(() => Session.logIn(_phone, code), 'Invalid code. Please try again.');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: SfColors.surface2,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(SfSpace.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(SfSpace.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Center(child: SokoMark(size: 56)),
                    const SizedBox(height: SfSpace.md),
                    Text('Soko Fetch Admin',
                        textAlign: TextAlign.center,
                        style: text.headlineSmall),
                    const SizedBox(height: SfSpace.xs),
                    Text(
                      _codeSent
                          ? 'If $_phone is an admin number, a code has been sent to it.'
                          : 'Sign in with your admin phone number.',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: SfSpace.lg),
                    TextField(
                      controller: _phoneCtrl,
                      enabled: !_codeSent && !_loading,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
                      ],
                      decoration: const InputDecoration(
                        labelText: 'Phone number',
                        hintText: '0712 345 678',
                        prefixIcon: Icon(Icons.phone_outlined),
                      ),
                      onSubmitted: (_) => _sendCode(),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: SfSpace.sm),
                      TextField(
                        controller: _codeCtrl,
                        autofocus: true,
                        enabled: !_loading,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: const InputDecoration(
                          labelText: '6-digit code',
                          prefixIcon: Icon(Icons.sms_outlined),
                          counterText: '',
                        ),
                        onSubmitted: (_) => _logIn(),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: SfSpace.sm),
                      InlineMessage(_error!),
                    ],
                    const SizedBox(height: SfSpace.lg),
                    SfButton.primary(
                      label: _codeSent ? 'Sign in' : 'Send code',
                      loading: _loading,
                      onPressed: _codeSent ? _logIn : _sendCode,
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: SfSpace.xs),
                      Center(
                        child: SfButton.text(
                          label: 'Use a different number',
                          onPressed: _loading
                              ? null
                              : () => setState(() {
                                    _codeSent = false;
                                    _codeCtrl.clear();
                                    _error = null;
                                  }),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
