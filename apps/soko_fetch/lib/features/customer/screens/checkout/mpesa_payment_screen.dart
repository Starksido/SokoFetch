import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_client.dart';
import '../../../../core/errors.dart';
import '../../../../core/session.dart';
import '../../../../core/ui/ui.dart';

/// Pay for an order with an M-Pesa push: send the request, approve it on the
/// phone, then wait for the payment to be confirmed.
class MpesaPaymentScreen extends ConsumerStatefulWidget {
  const MpesaPaymentScreen({super.key});
  @override
  ConsumerState<MpesaPaymentScreen> createState() => _MpesaPaymentScreenState();
}

class _MpesaPaymentScreenState extends ConsumerState<MpesaPaymentScreen> {
  final _phoneCtrl = TextEditingController();
  bool _initiating = false;
  bool _waiting = false;
  String? _error;
  String? _orderId;
  num? _total;
  int _pollCount = 0;
  Timer? _pollTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_orderId != null) return;
    _orderId = ModalRoute.of(context)!.settings.arguments as String;
    final phone = ref.read(currentUserProvider)?.phone;
    if (phone != null) _phoneCtrl.text = '0${phone.replaceFirst('+254', '')}';
    _loadTotal();
  }

  Future<void> _loadTotal() async {
    try {
      final resp = await ApiClient.instance.get('/orders/$_orderId');
      final total = (resp.data as Map)['total'];
      if (mounted && total != null) {
        setState(() => _total = num.tryParse(total.toString()));
      }
    } catch (_) {
      // The amount is shown on the M-Pesa prompt too
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _initiatePush() async {
    if (_phoneCtrl.text.trim().length < 9) {
      setState(() => _error = 'Enter the M-Pesa number to pay from.');
      return;
    }
    setState(() { _initiating = true; _error = null; });
    try {
      await ApiClient.instance.post('/payments/mpesa/initiate', data: {
        'order_id': _orderId,
        'phone': _phoneCtrl.text.trim(),
      });
      setState(() { _initiating = false; _waiting = true; _pollCount = 0; });
      _startPolling();
    } catch (e) {
      setState(() {
        _initiating = false;
        _error = errorMessage(
            e, "Couldn't send the payment request. Check the number and try again.");
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      _pollCount++;
      if (_pollCount > 24) { // Two minutes
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _waiting = false;
            _error = "We didn't get the payment in time. Please try again.";
          });
        }
        return;
      }
      try {
        final resp = await ApiClient.instance.get('/orders/$_orderId');
        if ((resp.data as Map)['payment_status'] == 'paid') {
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Pay with M-Pesa')),
      bottomNavigationBar: _waiting
          ? SafeArea(
              minimum: const EdgeInsets.all(SfSpace.md),
              child: SfButton.secondary(
                label: 'Use a different number',
                onPressed: () => setState(() {
                  _waiting = false;
                  _pollTimer?.cancel();
                }),
              ),
            )
          : BottomCtaBar(
              label: 'Send payment request',
              amount: _total,
              loading: _initiating,
              onPressed: _initiatePush,
            ),
      body: MaxWidth(
        maxWidth: 520,
        child: ListView(
          padding: const EdgeInsets.all(SfSpace.lg),
          children: [
            _Steps(step: _waiting ? 1 : 0),
            const SizedBox(height: SfSpace.xl),
            if (_waiting) ...[
              const SizedBox(
                  height: 40,
                  width: 40,
                  child: Center(child: CircularProgressIndicator())),
              const SizedBox(height: SfSpace.lg),
              Text('Check your phone', style: text.headlineMedium),
              const SizedBox(height: SfSpace.xs),
              Text(
                'We sent an M-Pesa request to ${_phoneCtrl.text.trim()}. '
                'Enter your M-Pesa PIN to pay'
                '${_total != null ? ' ${formatKes(_total!)}' : ''}. '
                "This page moves on by itself once it's paid.",
                style: text.bodyLarge!.copyWith(color: SfColors.inkMuted),
              ),
            ] else ...[
              Text('Pay${_total != null ? ' ${formatKes(_total!)}' : ''}',
                  style: text.headlineMedium),
              const SizedBox(height: SfSpace.xs),
              Text(
                "Enter the M-Pesa number to pay from. You'll get a prompt on that phone.",
                style: text.bodyLarge!.copyWith(color: SfColors.inkMuted),
              ),
              const SizedBox(height: SfSpace.lg),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9+]'))
                ],
                decoration: const InputDecoration(
                  hintText: '0712 345 678',
                  prefixIcon: Icon(Icons.phone_iphone_rounded),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: SfSpace.sm),
                InlineMessage(_error!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 1 Send request → 2 Approve on phone → 3 Paid
class _Steps extends StatelessWidget {
  const _Steps({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    const labels = ['Send request', 'Approve on phone', 'Paid'];
    return Row(children: [
      for (var i = 0; i < labels.length; i++)
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i < labels.length - 1 ? SfSpace.xs : 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 4,
                decoration: BoxDecoration(
                  color: i <= step ? SfColors.brand : SfColors.surface3,
                  borderRadius: SfRadius.pillAll,
                ),
              ),
              const SizedBox(height: SfSpace.xs),
              Text(labels[i],
                  style: text.labelSmall!.copyWith(
                      color: i <= step ? SfColors.accentStrong : SfColors.inkFaint)),
            ]),
          ),
        ),
    ]);
  }
}
