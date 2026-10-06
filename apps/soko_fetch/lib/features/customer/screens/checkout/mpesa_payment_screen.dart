import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme.dart';
import '../../../../core/api_client.dart';

class MpesaPaymentScreen extends StatefulWidget {
  const MpesaPaymentScreen({super.key});
  @override
  State<MpesaPaymentScreen> createState() => _MpesaPaymentScreenState();
}

class _MpesaPaymentScreenState extends State<MpesaPaymentScreen> {
  final _phoneCtrl = TextEditingController();
  bool _initiating  = false;
  bool _waiting     = false;
  String? _error;
  String? _checkoutId;
  late String _orderId;
  int _pollCount = 0;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _orderId = ModalRoute.of(context)!.settings.arguments as String;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _initiatePush() async {
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter your M-Pesa phone number.');
      return;
    }
    setState(() { _initiating = true; _error = null; });
    try {
      final resp = await ApiClient.instance
          .post('/payments/mpesa/initiate', data: {
        'order_id': _orderId,
        'phone':    _phoneCtrl.text.trim(),
      });
      _checkoutId = (resp.data as Map)['checkout_request_id'] as String?;
      setState(() { _initiating = false; _waiting = true; });
      _startPolling();
    } catch (e) {
      setState(() {
        _initiating = false;
        _error = 'Failed to send STK Push. Check your number and retry.';
      });
    }
  }

  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      _pollCount++;
      if (_pollCount > 24) {   // Stop after 2 minutes
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _waiting = false;
            _error   = 'Payment timed out. Please try again.';
          });
        }
        return;
      }
      try {
        final resp = await ApiClient.instance
            .get('/orders/$_orderId');
        final status = (resp.data as Map)['payment_status'] as String?;
        if (status == 'paid') {
          _pollTimer?.cancel();
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/customer/tracking',
              arguments: _orderId);
        }
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('M-Pesa Payment')),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: _waiting ? _waitingView() : _enterPhoneView(),
      ),
    );
  }

  Widget _enterPhoneView() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.phone_android, size: 56, color: AppTheme.teal),
          const SizedBox(height: 20),
          const Text('Pay with M-Pesa',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 8),
          const Text(
              'Enter your M-Pesa number below. You\'ll receive a payment prompt on your phone.',
              style: TextStyle(color: AppTheme.mgray)),
          const SizedBox(height: 32),
          TextFormField(
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
            ],
            decoration: const InputDecoration(
              labelText: 'M-Pesa Phone Number',
              hintText: '0712 345 678',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_error!,
                  style: const TextStyle(color: AppTheme.accent)),
            ),
          ],
          const SizedBox(height: 28),
          ElevatedButton(
            onPressed: _initiating ? null : _initiatePush,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: AppTheme.teal),
            child: _initiating
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Send Payment Request',
                    style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      );

  Widget _waitingView() => Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
              color: AppTheme.teal, strokeWidth: 3),
          const SizedBox(height: 32),
          const Text('Check your phone!',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22)),
          const SizedBox(height: 12),
          const Text(
              'An M-Pesa payment prompt has been sent to your phone.\n'
              'Enter your PIN to complete the payment.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.mgray)),
          const SizedBox(height: 40),
          TextButton(
            onPressed: () => setState(() {
              _waiting    = false;
              _pollCount  = 0;
              _pollTimer?.cancel();
            }),
            child: const Text('Try a different number',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      );
}

