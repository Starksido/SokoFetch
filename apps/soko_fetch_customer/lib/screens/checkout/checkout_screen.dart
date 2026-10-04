import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../network/secure_client.dart';
import '../../providers/providers.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _addressCtrl = TextEditingController();
  String _paymentMethod = 'mpesa';
  bool _placing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    if (_addressCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Please enter a delivery address.');
      return;
    }

    final cart        = ref.read(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    if (cart.isEmpty || cartNotifier.merchantId == null) return;

    setState(() { _placing = true; _error = null; });

    try {
      final resp = await SecureApiClient.instance.post('/orders', data: {
        'merchant_id':      cartNotifier.merchantId,
        'items': cart.map((c) => {
              'item_id':  c.item.id,
              'quantity': c.quantity,
            }).toList(),
        'delivery_address': _addressCtrl.text.trim(),
        'payment_method':   _paymentMethod,
      });

      final orderId = (resp.data as Map)['id'] as String;
      cartNotifier.clear();

      if (!mounted) return;
      if (_paymentMethod == 'mpesa') {
        Navigator.pushReplacementNamed(context, '/mpesa-payment',
            arguments: orderId);
      } else {
        Navigator.pushReplacementNamed(context, '/tracking',
            arguments: orderId);
      }
    } on DioException catch (e) {
      final msg = (e.response?.data as Map?)?['detail']?['message']
          as String? ?? 'Failed to place order.';
      setState(() { _error = msg; _placing = false; });
    } catch (_) {
      setState(() { _error = 'Something went wrong.'; _placing = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart        = ref.watch(cartProvider);
    final cartNotifier = ref.read(cartProvider.notifier);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Order summary
          _Section(
            title: 'Order Summary',
            child: Column(
              children: [
                ...cart.map((c) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${c.item.name} ×${c.quantity}',
                              style: const TextStyle(fontSize: 13)),
                          Text('KES ${c.lineTotal.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    )),
                const Divider(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Subtotal',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    Text('KES ${cartNotifier.subtotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Delivery address
          _Section(
            title: 'Delivery Address',
            child: TextField(
              controller: _addressCtrl,
              maxLines: 2,
              decoration: const InputDecoration(
                hintText: 'Enter your delivery address',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Payment method
          _Section(
            title: 'Payment Method',
            child: Column(
              children: [
                _PaymentOption(
                  value: 'mpesa',
                  groupValue: _paymentMethod,
                  label: 'M-Pesa',
                  icon: Icons.phone_android,
                  onChanged: (v) => setState(() => _paymentMethod = v!),
                ),
                // Card is hidden until the Flutterwave SDK + /payments/card/verify
                // are wired up — selecting it used to skip payment entirely.
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10)),
              child: Text(_error!,
                  style: const TextStyle(color: AppTheme.accent)),
            ),
          ],
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed: _placing ? null : _placeOrder,
            style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(54)),
            child: _placing
                ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Text('Place Order',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text('Payment is collected before your rider is dispatched.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppTheme.mgray, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 12),
          child,
        ]),
      );
}

class _PaymentOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final String label;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  const _PaymentOption(
      {required this.value,
      required this.groupValue,
      required this.label,
      required this.icon,
      required this.onChanged});

  @override
  Widget build(BuildContext context) => RadioListTile<String>(
        value: value,
        groupValue: groupValue,
        onChanged: onChanged,
        activeColor: AppTheme.accent,
        title: Row(children: [
          Icon(icon, size: 20, color: AppTheme.mgray),
          const SizedBox(width: 8),
          Text(label),
        ]),
        contentPadding: EdgeInsets.zero,
      );
}

