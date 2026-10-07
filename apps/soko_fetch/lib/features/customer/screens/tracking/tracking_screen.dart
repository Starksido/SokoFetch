import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config.dart';
import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  GoogleMapController? _mapController;
  Timer? _poll;
  OrderTracking? _tracking;
  late String _orderId;
  Order? _order;
  String? _deliveryCode;
  bool _loadingOrder = true;
  bool _initialized = false;

  final Set<Marker> _markers = {};

  static const _headlines = {
    'pending': 'Waiting for the shop',
    'confirmed': 'Order confirmed',
    'preparing': 'The shop is preparing your order',
    'ready_for_pickup': 'Ready for pickup',
    'picked_up': 'Your rider has your order',
    'in_transit': 'On the way to you',
    'delivered': 'Delivered',
    'cancelled': 'Order cancelled',
    'delivery_failed': "Delivery didn't go through",
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    _orderId = ModalRoute.of(context)!.settings.arguments as String;
    _loadOrder();
    _pollTracking();
    _poll = Timer.periodic(
        AppConfig.trackingPollInterval, (_) => _pollTracking());
  }

  bool get _isTerminal =>
      _order?.isDelivered == true ||
      _order?.isCancelled == true ||
      _order?.status == 'delivery_failed';

  Future<void> _loadOrder() async {
    try {
      final resp = await ApiClient.instance.get('/orders/$_orderId');
      if (!mounted) return;
      setState(() {
        _order = Order.fromJson(resp.data as Map<String, dynamic>);
        _loadingOrder = false;
        _rebuildMarkers();
      });
      if (_isTerminal) _poll?.cancel();
      _loadDeliveryCode();
    } catch (_) {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  /// The rider needs this code to complete delivery. Only exists once paid.
  Future<void> _loadDeliveryCode() async {
    final order = _order;
    if (_deliveryCode != null || order == null) return;
    if (order.paymentStatus != 'paid' || !order.isActive) return;
    try {
      final resp =
          await ApiClient.instance.get('/orders/$_orderId/delivery-code');
      if (!mounted) return;
      setState(() => _deliveryCode =
          (resp.data as Map<String, dynamic>)['delivery_code'] as String?);
    } catch (_) {
      // Retried on the next status change
    }
  }

  /// Status, rider and rider position. Reloads the full order when the
  /// status moves on, so totals, the delivery code and Cancel stay right.
  Future<void> _pollTracking() async {
    try {
      final resp = await ApiClient.instance.get('/orders/$_orderId/tracking');
      if (!mounted) return;
      final tracking =
          OrderTracking.fromJson(resp.data as Map<String, dynamic>);
      final statusChanged = _order != null && tracking.status != _order!.status;
      setState(() {
        _tracking = tracking;
        _rebuildMarkers();
      });
      final pos = tracking.position;
      if (pos != null) {
        _mapController?.animateCamera(CameraUpdate.newLatLng(pos));
      }
      if (statusChanged) await _loadOrder();
    } catch (_) {
      // Keep the last known state; the next poll tries again
    }
  }

  void _rebuildMarkers() {
    _markers.clear();
    final rider = _tracking?.position;
    if (rider != null) {
      _markers.add(Marker(
        markerId: const MarkerId('courier'),
        position: rider,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: InfoWindow(title: _tracking?.courierName ?? 'Your Rider'),
      ));
    }
    if (_order?.deliveryLatitude != null && _order?.deliveryLongitude != null) {
      _markers.add(Marker(
        markerId: const MarkerId('delivery'),
        position: LatLng(_order!.deliveryLatitude!, _order!.deliveryLongitude!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Delivery Location'),
      ));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  String get _subline {
    final status = _order?.status ?? _tracking?.status;
    final eta = _order?.estimatedDeliveryAt;
    if (status == 'delivered') return 'Enjoy! Let us know how it went.';
    if (status == 'cancelled' || status == 'delivery_failed') {
      return _order?.cancellationReason ?? 'Contact support if you were charged.';
    }
    if (status == 'pending') return 'The shop will confirm your order shortly.';
    return eta != null ? 'Estimated arrival ${_formatTime(eta)}' : 'Arriving soon';
  }

  /// 0..3: placed, preparing, on the way, delivered
  int _stepFor(String status) => switch (status) {
        'pending' || 'confirmed' => 0,
        'preparing' || 'ready_for_pickup' => 1,
        'picked_up' || 'in_transit' => 2,
        'delivered' => 3,
        _ => 0,
      };

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: const Text("The shop hasn't started on it yet, so you can still cancel."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep order')),
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: TextButton.styleFrom(foregroundColor: SfColors.danger),
              child: const Text('Cancel order')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.instance.post('/orders/$_orderId/cancel');
      _loadOrder();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final status = _order?.status ?? _tracking?.status ?? 'pending';
    final riderPos = _tracking?.position;
    final order = _order;

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          bottom: MediaQuery.sizeOf(context).height * 0.4,
          child: AppConfig.mapsEnabled
              ? GoogleMap(
                  initialCameraPosition: CameraPosition(
                    target: riderPos ?? const LatLng(-1.2921, 36.8219),
                    zoom: 14,
                  ),
                  markers: _markers,
                  onMapCreated: (c) => _mapController = c,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                )
              : MapPlaceholder(
                  icon: riderPos != null
                      ? Icons.delivery_dining_rounded
                      : Icons.storefront_rounded),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SfSpace.xs),
            child: Row(children: [
              SfCircleButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.maybePop(context),
              ),
              const Spacer(),
              if (order?.canCancel == true)
                Material(
                  color: SfColors.surface,
                  shape: const StadiumBorder(),
                  child: TextButton(
                    onPressed: _cancelOrder,
                    child: const Text('Cancel order'),
                  ),
                ),
            ]),
          ),
        ),
        DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.35,
          maxChildSize: 0.92,
          builder: (context, scroll) => DecoratedBox(
            decoration: const BoxDecoration(
              color: SfColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(SfRadius.lg)),
              boxShadow: SfShadow.floating,
            ),
            child: _loadingOrder
                ? const LoadingList(count: 3)
                : ListView(
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(
                        SfSpace.md, SfSpace.xs, SfSpace.md, SfSpace.xl),
                    children: [
                      Center(
                        child: Container(
                          width: 36,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: SfSpace.md),
                          decoration: const BoxDecoration(
                              color: SfColors.surface3,
                              borderRadius: SfRadius.pillAll),
                        ),
                      ),
                      Text(_headlines[status] ?? orderStatusStyle(status).$1,
                          style: text.headlineSmall),
                      const SizedBox(height: SfSpace.xxs),
                      Text(_subline, style: text.bodyLarge!.copyWith(color: SfColors.inkMuted)),
                      if (status != 'cancelled' && status != 'delivery_failed') ...[
                        const SizedBox(height: SfSpace.md),
                        _Progress(step: _stepFor(status)),
                      ],
                      if (_tracking?.courierAssigned == true &&
                          status != 'delivered') ...[
                        const SizedBox(height: SfSpace.lg),
                        Row(children: [
                          InitialsAvatar(name: _tracking?.courierName ?? 'Rider'),
                          const SizedBox(width: SfSpace.sm),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_tracking?.courierName ?? 'Your rider',
                                    style: text.titleSmall),
                                if (_tracking?.vehicleType != null)
                                  Text(
                                      _tracking!.vehicleType!.replaceAll('_', ' '),
                                      style: text.bodyMedium),
                              ],
                            ),
                          ),
                        ]),
                      ],
                      if (_deliveryCode != null && !_isTerminal) ...[
                        const SizedBox(height: SfSpace.lg),
                        _DeliveryCodeCard(code: _deliveryCode!),
                      ],
                      if (order?.canRate == true) ...[
                        const SizedBox(height: SfSpace.lg),
                        SfButton.primary(
                          label: 'Rate your order',
                          icon: Icons.star_outline_rounded,
                          onPressed: () => Navigator.pushReplacementNamed(
                              context, '/customer/rate-order',
                              arguments: _orderId),
                        ),
                      ],
                      if (order != null) ...[
                        const SizedBox(height: SfSpace.lg),
                        const Divider(),
                        const SizedBox(height: SfSpace.md),
                        Text(order.merchantName ?? 'Your order', style: text.titleMedium),
                        const SizedBox(height: SfSpace.xs),
                        for (final raw in order.items)
                          if (raw is Map)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(children: [
                                SizedBox(
                                    width: 32,
                                    child: Text('${raw['qty']}×', style: text.bodyMedium)),
                                Expanded(
                                    child: Text('${raw['name']}', style: text.bodyLarge)),
                                Text(formatKes(parseNum(raw['subtotal'])),
                                    style: text.bodyLarge),
                              ]),
                            ),
                        const SizedBox(height: SfSpace.xs),
                        Row(children: [
                          Expanded(child: Text('Delivery', style: text.bodyMedium)),
                          Text(formatKes(order.deliveryFee), style: text.bodyMedium),
                        ]),
                        const SizedBox(height: SfSpace.xxs),
                        Row(children: [
                          Expanded(child: Text('Total', style: text.titleSmall)),
                          Text(formatKes(order.total), style: text.titleSmall),
                        ]),
                        const SizedBox(height: SfSpace.md),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Icon(Icons.place_outlined, size: 20, color: SfColors.inkMuted),
                          const SizedBox(width: SfSpace.xs),
                          Expanded(child: Text(order.deliveryAddress, style: text.bodyMedium)),
                        ]),
                      ],
                    ],
                  ),
          ),
        ),
      ]),
    );
  }
}

/// Four segments: placed, preparing, on the way, delivered.
class _Progress extends StatelessWidget {
  const _Progress({required this.step});
  final int step;

  @override
  Widget build(BuildContext context) => Row(children: [
        for (var i = 0; i < 4; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < 3 ? SfSpace.xxs : 0),
              decoration: BoxDecoration(
                color: i <= step ? SfColors.ink : SfColors.surface3,
                borderRadius: SfRadius.pillAll,
              ),
            ),
          ),
      ]);
}

class _DeliveryCodeCard extends StatelessWidget {
  const _DeliveryCodeCard({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(SfSpace.md),
      decoration: const BoxDecoration(
          color: SfColors.surface2, borderRadius: SfRadius.mdAll),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Delivery code', style: text.titleSmall),
            const SizedBox(height: 2),
            Text('Give this to your rider when your order arrives',
                style: text.bodySmall),
          ]),
        ),
        Text(code,
            style: text.displaySmall!.copyWith(letterSpacing: 4),
            semanticsLabel: 'Delivery code ${code.split('').join(' ')}'),
      ]),
    );
  }
}
