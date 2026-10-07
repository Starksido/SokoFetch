import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/api_client.dart';
import '../../../core/errors.dart';
import '../../../core/ui/ui.dart';
import '../models/models.dart';
import '../providers/providers.dart';

/// Pick where to deliver, or add a new address.
Future<void> showAddressSheet(BuildContext context) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _AddressSheet(),
    );

class _AddressSheet extends ConsumerStatefulWidget {
  const _AddressSheet();

  @override
  ConsumerState<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends ConsumerState<_AddressSheet> {
  bool _adding = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final addresses = ref.watch(addressesProvider);
    final selected = ref.watch(selectedAddressProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            SfSpace.md, 0, SfSpace.md, SfSpace.lg),
        child: _adding
            ? _AddAddressForm(onDone: () => setState(() => _adding = false))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Deliver to', style: text.titleLarge),
                  const SizedBox(height: SfSpace.sm),
                  addresses.when(
                    loading: () => const Padding(
                        padding: EdgeInsets.all(SfSpace.lg), child: SfLoader()),
                    error: (e, _) => InlineMessage(
                        errorMessage(e, "Couldn't load your addresses.")),
                    data: (list) => Column(children: [
                      if (list.isEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: SfSpace.sm),
                          child: Text(
                              'Add an address so riders know where to bring your order.',
                              style: text.bodyMedium),
                        ),
                      for (final a in list)
                        _AddressTile(
                          address: a,
                          selected: a.id == selected?.id,
                          onTap: () {
                            ref.read(selectedAddressIdProvider.notifier).state = a.id;
                            Navigator.pop(context);
                          },
                        ),
                    ]),
                  ),
                  const SizedBox(height: SfSpace.sm),
                  SfButton.secondary(
                    label: 'Add an address',
                    icon: Icons.add_rounded,
                    onPressed: () => setState(() => _adding = true),
                  ),
                ],
              ),
      ),
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile(
      {required this.address, required this.selected, required this.onTap});

  final DeliveryAddress address;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return InkWell(
      onTap: onTap,
      borderRadius: SfRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SfSpace.sm),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
                color: SfColors.surface2, shape: BoxShape.circle),
            child: Icon(
                address.label.toLowerCase() == 'work'
                    ? Icons.work_outline_rounded
                    : address.label.toLowerCase() == 'home'
                        ? Icons.home_outlined
                        : Icons.place_outlined,
                size: 20),
          ),
          const SizedBox(width: SfSpace.sm),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(address.label, style: text.titleSmall),
              Text(address.fullAddress,
                  style: text.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ]),
          ),
          if (selected) const Icon(Icons.check_rounded, color: SfColors.brand),
        ]),
      ),
    );
  }
}

class _AddAddressForm extends ConsumerStatefulWidget {
  const _AddAddressForm({required this.onDone});
  final VoidCallback onDone;

  @override
  ConsumerState<_AddAddressForm> createState() => _AddAddressFormState();
}

class _AddAddressFormState extends ConsumerState<_AddAddressForm> {
  final _formKey = GlobalKey<FormState>();
  final _address = TextEditingController();
  final _instructions = TextEditingController();
  String _label = 'Home';
  bool _usePin = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _address.dispose();
    _instructions.dispose();
    super.dispose();
  }

  /// The phone's location, if the customer allows it. Riders and delivery
  /// pricing use it; the typed address is still sent either way.
  Future<Position?> _position() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return null;
      }
      return await Geolocator.getCurrentPosition()
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      return null;
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _saving = true; _error = null; });
    try {
      final pos = _usePin ? await _position() : null;
      final isFirst = (ref.read(addressesProvider).valueOrNull ?? []).isEmpty;
      final resp = await ApiClient.instance.post('/customer/addresses', data: {
        'label': _label,
        'address_line': _address.text.trim(),
        if (_instructions.text.trim().isNotEmpty)
          'instructions': _instructions.text.trim(),
        if (pos != null) 'latitude': pos.latitude,
        if (pos != null) 'longitude': pos.longitude,
        'is_default': isFirst,
      });
      final id = (resp.data as Map)['id'].toString();
      ref.invalidate(addressesProvider);
      ref.read(selectedAddressIdProvider.notifier).state = id;
      if (mounted) widget.onDone();
    } catch (e) {
      if (mounted) {
        setState(() => _error = errorMessage(e, "Couldn't save the address."));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            IconButton(
              onPressed: widget.onDone,
              icon: const Icon(Icons.arrow_back_rounded),
              tooltip: 'Back',
            ),
            Text('New address', style: text.titleLarge),
          ]),
          const SizedBox(height: SfSpace.xs),
          Wrap(spacing: SfSpace.xs, children: [
            for (final l in const ['Home', 'Work', 'Other'])
              ChoiceChip(
                label: Text(l),
                selected: _label == l,
                onSelected: (_) => setState(() => _label = l),
              ),
          ]),
          const SizedBox(height: SfSpace.md),
          TextFormField(
            controller: _address,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Street, building, house number',
              prefixIcon: Icon(Icons.place_outlined),
            ),
            validator: (v) => (v == null || v.trim().length < 5)
                ? 'Enter the full address'
                : null,
          ),
          const SizedBox(height: SfSpace.sm),
          TextFormField(
            controller: _instructions,
            decoration: const InputDecoration(
              hintText: 'Directions for the rider (optional)',
              prefixIcon: Icon(Icons.notes_rounded),
            ),
          ),
          const SizedBox(height: SfSpace.xs),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _usePin,
            onChanged: (v) => setState(() => _usePin = v),
            title: Text('Pin my current location', style: text.titleSmall),
            subtitle: Text('Helps riders find you', style: text.bodySmall),
          ),
          if (_error != null) ...[
            InlineMessage(_error!),
            const SizedBox(height: SfSpace.sm),
          ],
          SfButton.primary(
              label: 'Save address', loading: _saving, onPressed: _save),
        ],
      ),
    );
  }
}
