import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../config/app_config.dart';
import '../../config/app_theme.dart';
import '../../models/models.dart';
import '../../network/secure_client.dart';

class TrackingScreen extends ConsumerStatefulWidget {
  const TrackingScreen({super.key});

  @override
  ConsumerState<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends ConsumerState<TrackingScreen> {
  GoogleMapController? _mapController;
  WebSocketChannel? _ws;
  CourierLocation? _courierLocation;
  StreamSubscription? _wsSub;
  late String _orderId;
  Order? _order;
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
    _connectWebSocket();
  }

  Future<void> _loadOrder() async {
    try {
      final resp = await SecureApiClient.instance.get('/orders/$_orderId');
      if (!mounted) return;
      setState(() {
        _order = Order.fromJson(resp.data as Map<String, dynamic>);
        _loadingOrder = false;
        _rebuildMarkers();
      });
    } catch (_) {
      if (mounted) setState(() => _loadingOrder = false);
    }
  }

  void _connectWebSocket() async {
    final token = await SecureApiClient.getAccessToken();
    if (token == null) return;

    try {
      _ws = WebSocketChannel.connect(
          Uri.parse(AppConfig.trackingWsUrl(_orderId)));
      _wsSub = _ws!.stream.listen((raw) {
        if (!mounted) return;
        try {
          final data = jsonDecode(raw as String) as Map<String, dynamic>;
          final loc = CourierLocation.fromJson(data);
          setState(() {
            _courierLocation = loc;
            _rebuildMarkers();
          });
          _mapController?.animateCamera(
            CameraUpdate.newLatLng(LatLng(loc.latitude, loc.longitude)),
          );
        } catch (_) {}
      });
    } catch (_) {}

    Timer.periodic(const Duration(seconds: 15), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_order?.isDelivered == true || _order?.isCancelled == true) {
        timer.cancel();
        return;
      }
      _loadOrder();
    });
  }

  void _rebuildMarkers() {
    _markers.clear();
    if (_courierLocation != null) {
      _markers.add(Marker(
        markerId: const MarkerId('courier'),
        position:
            LatLng(_courierLocation!.latitude, _courierLocation!.longitude),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
        infoWindow: const InfoWindow(title: 'Your Rider'),
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
    _wsSub?.cancel();
    _ws?.sink.close();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = _order?.status ?? 'pending';
    final isTerminal =
        _order?.isDelivered == true || _order?.isCancelled == true;
    final eta = _courierLocation?.etaMinutes;

    return Scaffold(
      backgroundColor: AppTheme.lgray,
      body: Stack(
        children: [
          Positioned.fill(
            child: GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _courierLocation != null
                    ? LatLng(
                        _courierLocation!.latitude, _courierLocation!.longitude)
                    : const LatLng(-1.2921, 36.8219),
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
                  : 'Rider on the move',
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
                    statusLabel: _statusLabels[status] ?? status,
                    etaLabel: eta != null
                        ? '$eta mins'
                        : _order?.estimatedDeliveryAt != null
                            ? _formatTime(_order!.estimatedDeliveryAt!)
                            : 'Soon',
                    progress: _progressFor(status),
                    isTerminal: isTerminal,
                    onRate: _order?.isDelivered == true
                        ? () => Navigator.pushReplacementNamed(
                              context,
                              '/rate-order',
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
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  Future<void> _cancelOrder() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Order'),
        content: const Text('Are you sure you want to cancel this order?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, cancel',
                style: TextStyle(color: AppTheme.accent)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await SecureApiClient.instance.post('/orders/$_orderId/cancel');
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
          color: Colors.white.withOpacity(0.9),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppTheme.outlineVariant.withOpacity(0.5)),
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
  final String statusLabel;
  final String etaLabel;
  final double progress;
  final bool isTerminal;
  final VoidCallback? onRate;

  const _TrackingSheet({
    required this.order,
    required this.statusLabel,
    required this.etaLabel,
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
                        isTerminal
                            ? 'Thanks for using Soko Fetch.'
                            : 'Rider is $etaLabel away.',
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
