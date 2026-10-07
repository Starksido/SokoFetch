import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/api_client.dart';
import '../../../../core/errors.dart';
import '../../../../core/ui/ui.dart';
import '../../providers/providers.dart';
import '../../widgets/address_sheet.dart';

class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});
  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _typedAddress = TextEditingController();
  final _note = TextEditingController();
  bool _typeAddress = false; // Use a one-off typed address instead of a saved one
  bool _placing = false;
  String? _error;

  @override
  void dispose() {
    _typedAddress.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _placeOrder() async {
    final saved = ref.read(selectedAddressProvider);
    final useTyped = _typeAddress || saved == null;
    final address = useTyped ? _typedAddress.text.trim() : saved.fullAddress;
    if (address.length < 5) {
      setState(() => _error = 'Add the address to deliver to.');
      return;
    }

    final cart = ref.read(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    if (cart.isEmpty || notifier.merchantId == null) return;

    setState(() { _placing = true; _error = null; });
    try {
      final note = [
        if (!useTyped && saved.instructions != null) saved.instructions!,
        if (_note.text.trim().isNotEmpty) _note.text.trim(),
      ].join(' · ');
      final resp = await ApiClient.instance.post('/orders', data: {
        'merchant_id': notifier.merchantId,
        'items': [
          for (final c in cart) {'item_id': c.item.id, 'quantity': c.quantity},
        ],
        'delivery_address': address,
        if (!useTyped && saved.latitude != null) 'delivery_latitude': saved.latitude,
        if (!useTyped && saved.longitude != null) 'delivery_longitude': saved.longitude,
        if (note.isNotEmpty) 'delivery_notes': note,
        'payment_method': 'mpesa',
      });
      final orderId = (resp.data as Map)['id'] as String;
      notifier.clear();
      ref.invalidate(ordersProvider);
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/customer/mpesa-payment',
          arguments: orderId);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = errorMessage(e, "Couldn't place the order. Please try again.");
          _placing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cart = ref.watch(cartProvider);
    final notifier = ref.read(cartProvider.notifier);
    final saved = ref.watch(selectedAddressProvider);
    final addressesLoading = ref.watch(addressesProvider).isLoading;
    final typed = _typeAddress || (saved == null && !addressesLoading);

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(SfSpace.md, SfSpace.xs, SfSpace.md, 0),
            child: InlineMessage(_error!),
          ),
        BottomCtaBar(
          label: 'Place order',
          loading: _placing,
          onPressed: cart.isEmpty ? null : _placeOrder,
        ),
      ]),
      body: MaxWidth(
        child: ListView(
          children: [
            // ── Delivery ─────────────────────────────────────────────────
            const SectionHeader('Delivery'),
            if (!typed && saved != null)
              ListRow(
                leading: const _RoundIcon(Icons.place_outlined),
                title: saved.label,
                subtitle: saved.fullAddress,
                trailing: TextButton(
                  onPressed: () => showAddressSheet(context),
                  child: const Text('Change'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
                child: TextField(
                  controller: _typedAddress,
                  maxLines: 2,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Street, building, house number',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.xs),
              child: Wrap(children: [
                if (saved != null)
                  TextButton(
                    onPressed: () => setState(() => _typeAddress = !_typeAddress),
                    child: Text(typed ? 'Use a saved address' : 'Type another address'),
                  ),
                TextButton(
                  onPressed: () => showAddressSheet(context),
                  child: const Text('Save an address'),
                ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SfSpace.md, 0, SfSpace.md, SfSpace.md),
              child: TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Note for the rider (optional)',
                  prefixIcon: Icon(Icons.notes_rounded),
                ),
              ),
            ),
            const SectionGap(),

            // ── Payment ──────────────────────────────────────────────────
            const SectionHeader('Payment'),
            const ListRow(
              leading: _RoundIcon(Icons.phone_iphone_rounded),
              title: 'M-Pesa',
              subtitle: "You'll approve the payment on your phone",
              trailing: Icon(Icons.check_circle_rounded, color: SfColors.ink),
            ),
            // Card stays hidden until card payments are verified server-side
            const SizedBox(height: SfSpace.sm),
            const SectionGap(),

            // ── Summary ──────────────────────────────────────────────────
            const SectionHeader('Order summary'),
            for (final c in cart)
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: SfSpace.md, vertical: SfSpace.xxs),
                child: Row(children: [
                  SizedBox(
                      width: 32,
                      child: Text('${c.quantity}×', style: text.bodyMedium)),
                  Expanded(child: Text(c.item.name, style: text.bodyLarge)),
                  Text(formatKes(c.lineTotal), style: text.bodyLarge),
                ]),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: SfSpace.sm),
              child: Divider(indent: SfSpace.md, endIndent: SfSpace.md),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: SfSpace.md),
              child: Column(children: [
                Row(children: [
                  Expanded(child: Text('Subtotal', style: text.titleSmall)),
                  Text(formatKes(notifier.subtotal), style: text.titleSmall),
                ]),
                const SizedBox(height: SfSpace.xxs),
                Row(children: [
                  Expanded(child: Text('Delivery fee', style: text.bodyMedium)),
                  Text('Added when you order', style: text.bodyMedium),
                ]),
                const SizedBox(height: SfSpace.md),
                Text(
                  "You'll see the full total, including delivery, before you pay. "
                  'A rider is sent once the payment goes through.',
                  style: text.bodySmall,
                ),
              ]),
            ),
            const SizedBox(height: SfSpace.lg),
          ],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon(this.icon);
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration:
            const BoxDecoration(color: SfColors.surface2, shape: BoxShape.circle),
        child: Icon(icon, size: 20),
      );
}
