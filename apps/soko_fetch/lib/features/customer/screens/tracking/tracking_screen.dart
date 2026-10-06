import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../../core/config.dart';
import '../../../../core/theme.dart';
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

  final _statusLabels = const {
    'pending': 'Waiting for merchant...',
    'confirmed': 'Order confirmed!',
    'preparing': 'Merchant is preparing your order',
    'ready_for_pickup': 'Looking for a rider nearby',
    'picked_up': 'Rider picked up your order',
    'in_transit': 'Fetch in progress!',
    'delivered': 'Delivered!',
    'cancelled': 'Order cancelled',
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

  String get _riderLine {
    final t = _tracking;
    final eta = _order?.estimatedDeliveryAt;
    final when = eta != null ? ' · arriving ${_formatTime(eta)}' : '';
    if (t == null || !t.courierAssigned) return 'Waiting for a rider to accept.';
    final who = t.courierName ?? 'Your rider';
    return '$who is on the way$when.';
  }

  @override
  Widget build(BuildContext context) {
    final status = _order?.status ?? _tracking?.status ?? 'pending';
    final isTerminal = _isTerminal;
    final riderPos = _tracking?.position;

    return Scaffold(
      backgroundColor: AppTheme.lgray,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: riderPos ?? const LatLng(-1.2921, 36.8219),
                zoom: 14,
              ),
              markers: _markers,
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              myLocationButtonEnabled: false,
              zoomControlsEnabled: false,
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.maybePop(context),
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: AppTheme.accent),
                    ),
                    const Text(
                      'Soko Fetch',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    if (_order?.canCancel == true)
                      TextButton(
                        onPressed: _cancelOrder,
                        child: const Text('Cancel'),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 62,
            left: 16,
            right: 16,
            child: _MapStatusPill(
              label: isTerminal
                  ? (_order?.isDelivered == true
                      ? 'Fetch delivered'
                      : 'Fetch ended')
                  : riderPos != null
                      ? 'Rider on the move'
                      : 'Tracking your order',
              active: !isTerminal,
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16 + MediaQuery.of(context).padding.bottom,
            child: _loadingOrder
                ? const Card(
                    child: SizedBox(
                      height: 180,
                      child: Center(
                          child: CircularProgressIndicator(
                              color: AppTheme.accent)),
                    ),
                  )
                : _TrackingSheet(
                    order: _order,
                    deliveryCode: _deliveryCode,
                    statusLabel: _statusLabels[status] ?? status,
                    subtitle: _riderLine,
                    progress: _progressFor(status),
                    isTerminal: isTerminal,
                    onRate: _order?.isDelivered == true
                        ? () => Navigator.pushReplacementNamed(
                              context,
                              '/customer/rate-order',
                              arguments: _orderId,
                            )
                        : null,
                  ),
          ),
        ],
      ),
    );
  }

  double _progressFor(String status) {
    switch (status) {
      case 'pending':
        return 0.12;
      case 'confirmed':
        return 0.28;
      case 'preparing':
        return 0.45;
      case 'ready_for_pickup':
        return 0.58;
      case 'picked_up':
        return 0.72;
      case 'in_transit':
        return 0.84;
      case 'delivered':
        return 1;
      default:
        return 0.2;
    }
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour.toString().padLeft(2, '0');
    final m = local.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel Order'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Yes, cancel',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ApiClient.instance.post('/orders/$_orderId/cancel');
      _loadOrder();
    } catch (_) {}
  }
}

class _MapStatusPill extends StatelessWidget {
  final String label;
  final bool active;

  const _MapStatusPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x16000000), blurRadius: 12, offset: Offset(0, 4)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? AppTheme.teal : AppTheme.mgray,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: active ? AppTheme.teal : AppTheme.mgray,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TrackingSheet extends StatelessWidget {
  final Order? order;
  final String? deliveryCode;
  final String statusLabel;
  final String subtitle;
  final double progress;
  final bool isTerminal;
  final VoidCallback? onRate;

  const _TrackingSheet({
    required this.order,
    this.deliveryCode,
    required this.statusLabel,
    required this.subtitle,
    required this.progress,
    required this.isTerminal,
    this.onRate,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        statusLabel,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.brand,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isTerminal ? 'Thanks for using Soko Fetch.' : subtitle,
                        style: const TextStyle(color: AppTheme.mgray),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryFixed,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child:
                      const Icon(Icons.timer_rounded, color: AppTheme.accent),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _ProgressSteps(progress: progress),
            const SizedBox(height: 18),
            if (deliveryCode != null && !isTerminal) ...[
              _SummaryRow(
                icon: Icons.lock_outline_rounded,
                label: 'Delivery code — give this to your rider',
                value: deliveryCode!,
              ),
              const SizedBox(height: 10),
            ],
            if (order != null) ...[
              _SummaryRow(
                icon: Icons.receipt_long_rounded,
                label: 'Order total',
                value: 'KES ${order!.total.toStringAsFixed(0)}',
              ),
              const SizedBox(height: 10),
              _SummaryRow(
                icon: Icons.home_rounded,
                label: 'Delivery address',
                value: order!.deliveryAddress,
              ),
            ],
            if (onRate != null) ...[
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRate,
                icon: const Icon(Icons.star_outline_rounded),
                label: const Text('Rate your experience'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  final double progress;

  const _ProgressSteps({required this.progress});

  @override
  Widget build(BuildContext context) {
    const labels = ['Placed', 'Prepping', 'Shipping', 'Delivered'];
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 5,
            backgroundColor: AppTheme.surfaceHigh,
            valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var i = 0; i < labels.length; i++)
              Text(
                labels[i],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: i / (labels.length - 1) <= progress
                      ? FontWeight.w800
                      : FontWeight.w500,
                  color: i / (labels.length - 1) <= progress
                      ? AppTheme.accent
                      : AppTheme.mgray,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _SummaryRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppTheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: AppTheme.teal, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(color: AppTheme.mgray, fontSize: 12)),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
