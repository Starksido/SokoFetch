import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/config.dart';
import '../../../../core/errors.dart';
import '../../../../core/theme.dart';
import '../../models/models.dart';
import '../../../../core/api_client.dart';
import '../../providers/providers.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, this.onOpenProfile});

  /// Switches the shell to the Profile tab
  final VoidCallback? onOpenProfile;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Assignments arrive server-side; without push, poll while online.
  static const _orderPollInterval = Duration(seconds: 15);

  Timer? _locationTimer;
  Timer? _orderPollTimer;
  String? _activeOrderId;
  bool _toggling = false;

  @override
  void initState() {
    super.initState();
    _loadActiveOrder();
  }

  Future<void> _loadActiveOrder() async {
    final order = ref.read(activeOrderProvider).valueOrNull;
    if (order != null) setState(() => _activeOrderId = order.id);
  }

  Future<void> _toggleOnline(bool val, String courierId) async {
    if (_toggling) return;
    setState(() => _toggling = true);

    try {
      if (val) {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.deniedForever) {
          _showSnack('Location permission required to go online.');
          return;
        }
        await ApiClient.instance.put('/courier/online');
        ref.read(onlineProvider.notifier).set(true);
        WakelockPlus.enable();
        _startLocationUpdates(courierId);
        _startOrderPolling();
      } else {
        _locationTimer?.cancel();
        _orderPollTimer?.cancel();
        await ApiClient.instance.put('/courier/offline');
        ref.read(onlineProvider.notifier).set(false);
        WakelockPlus.disable();
      }
    } catch (_) {
      _showSnack('Failed to update status. Try again.');
    } finally {
      if (mounted) setState(() => _toggling = false);
    }
  }

  void _startLocationUpdates(String courierId) {
    _locationTimer?.cancel();
    _locationTimer =
        Timer.periodic(AppConfig.locationUpdateInterval, (_) async {
      try {
        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);
        await ApiClient.instance.put('/courier/location', data: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          if (_activeOrderId != null) 'order_id': _activeOrderId,
        });
      } catch (_) {}
    });
  }

  void _startOrderPolling() {
    _orderPollTimer?.cancel();
    _orderPollTimer = Timer.periodic(_orderPollInterval, (_) {
      if (mounted) ref.invalidate(activeOrderProvider);
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    _orderPollTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(courierProfileProvider);
    final isOnline = ref.watch(onlineProvider);
    final activeOrder = ref.watch(activeOrderProvider);

    return Scaffold(
      backgroundColor: AppTheme.lgray,
      appBar: AppBar(
        title: const Text('Soko Fetch'),
        actions: [
          IconButton(
            tooltip: 'Profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: widget.onOpenProfile,
          ),
        ],
      ),
      body: profileAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (_, __) => const Center(child: Text('Failed to load profile')),
        data: (profile) {
          if (profile.needsDocs ||
              profile.isPendingReview ||
              profile.isRejected) {
            return _VerificationPrompt(profile: profile);
          }

          return Column(
            children: [
              _OnlineToggleCard(
                isOnline: isOnline,
                toggling: _toggling,
                onToggle: (val) => _toggleOnline(val, profile.id),
                rating: profile.rating,
                deliveries: profile.totalDeliveries,
              ),
              Expanded(
                child: activeOrder.when(
                  loading: () => const Center(
                      child: CircularProgressIndicator(color: AppTheme.accent)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (order) {
                    if (order != null && order.isActive) {
                      _activeOrderId = order.id;
                      return _ActiveOrderCard(
                        order: order,
                        onStatusChanged: () {
                          ref.invalidate(activeOrderProvider);
                          setState(() => _activeOrderId = null);
                        },
                      );
                    }

                    _activeOrderId = null;
                    if (!isOnline) return const _WaitingView(isOnline: false);
                    return _JobBoard(
                      onAccepted: () => ref.invalidate(activeOrderProvider),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _OnlineToggleCard extends StatelessWidget {
  final bool isOnline;
  final bool toggling;
  final ValueChanged<bool> onToggle;
  final double rating;
  final int deliveries;

  const _OnlineToggleCard({
    required this.isOnline,
    required this.toggling,
    required this.onToggle,
    required this.rating,
    required this.deliveries,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isOnline ? const Color(0xFF5F1900) : AppTheme.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isOnline ? AppTheme.primaryContainer : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: isOnline
                  ? AppTheme.primaryContainer
                  : AppTheme.outlineVariant),
          boxShadow: const [
            BoxShadow(
                color: Color(0x12000000), blurRadius: 14, offset: Offset(0, 6)),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: isOnline
                    ? Colors.white.withValues(alpha: 0.22)
                    : AppTheme.primaryFixed,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                isOnline
                    ? Icons.bolt_rounded
                    : Icons.power_settings_new_rounded,
                color: isOnline ? textColor : AppTheme.accent,
                size: 30,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isOnline ? 'Priority requests enabled' : 'You are offline',
                    style: TextStyle(
                        color: textColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 16),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    isOnline
                        ? 'New fetches can arrive any moment.'
                        : 'Go online to start earning.',
                    style: TextStyle(
                        color: isOnline
                            ? textColor.withValues(alpha: 0.75)
                            : AppTheme.mgray,
                        fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.star_rounded,
                          color: AppTheme.gold, size: 15),
                      const SizedBox(width: 4),
                      Text(rating.toStringAsFixed(1),
                          style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12)),
                      const SizedBox(width: 12),
                      Icon(Icons.local_shipping_outlined,
                          color: isOnline ? textColor : AppTheme.mgray,
                          size: 15),
                      const SizedBox(width: 4),
                      Text('$deliveries deliveries',
                          style: TextStyle(
                              color: isOnline ? textColor : AppTheme.mgray,
                              fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            toggling
                ? SizedBox(
                    width: 44,
                    height: 44,
                    child: CircularProgressIndicator(
                        color: textColor, strokeWidth: 2.5),
                  )
                : Switch(
                    value: isOnline,
                    onChanged: onToggle,
                    activeColor: textColor,
                    inactiveThumbColor: AppTheme.accent,
                  ),
          ],
        ),
      ),
    );
  }
}

class _WaitingView extends StatelessWidget {
  final bool isOnline;

  const _WaitingView({required this.isOnline});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppTheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Icon(Icons.route_rounded,
                        size: 220, color: AppTheme.mgray.withValues(alpha: 0.08)),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            color:
                                isOnline ? AppTheme.primaryFixed : Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppTheme.outlineVariant),
                          ),
                          child: Icon(
                            isOnline
                                ? Icons.radar_rounded
                                : Icons.power_settings_new_outlined,
                            size: 46,
                            color: isOnline ? AppTheme.accent : AppTheme.mgray,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          isOnline
                              ? 'Looking for fetches nearby'
                              : 'You are offline',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              color: AppTheme.brand),
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Text(
                            isOnline
                                ? 'Keep this screen open. Priority requests will appear here.'
                                : 'Toggle online above to start accepting delivery requests.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: AppTheme.mgray, fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Expanded(
                  child: _MetricCard(
                      icon: Icons.payments_rounded,
                      label: 'Est. Earnings',
                      value: 'Live')),
              SizedBox(width: 12),
              Expanded(
                  child: _MetricCard(
                      icon: Icons.schedule_rounded,
                      label: 'Time Limit',
                      value: '15 mins')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatefulWidget {
  final Order order;
  final VoidCallback onStatusChanged;

  const _ActiveOrderCard({required this.order, required this.onStatusChanged});

  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard> {
  bool _acting = false;

  Future<void> _updateStatus(String status) async {
    if (_acting) return;
    setState(() => _acting = true);
    try {
      await ApiClient.instance
          .put('/orders/${widget.order.id}/status', data: {'status': status});
      widget.onStatusChanged();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Scrolls when space is short (small phones, keyboard open); otherwise
    // the map panel fills whatever the details card leaves
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: (constraints.maxHeight - 32).clamp(0.0, double.infinity)),
          child: IntrinsicHeight(child: _content(widget.order)),
        ),
      ),
    );
  }

  Widget _content(Order o) {
    return Column(
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              // Room for the "next step" banner even when space is tight
              constraints: const BoxConstraints(minHeight: 110),
              decoration: BoxDecoration(
                color: AppTheme.surfaceHigh,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppTheme.outlineVariant),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Icon(Icons.map_rounded,
                        size: 240, color: AppTheme.mgray.withValues(alpha: 0.08)),
                  ),
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                                color: AppTheme.accent,
                                borderRadius: BorderRadius.circular(14)),
                            child: const Icon(Icons.turn_slight_right_rounded,
                                color: Colors.white, size: 30),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('NEXT STEP',
                                    style: TextStyle(
                                        color: AppTheme.mgray,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700)),
                                Text('Follow pickup route',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 17)),
                              ],
                            ),
                          ),
                          Text('KES ${o.courierPayout.toStringAsFixed(0)}',
                              style: const TextStyle(
                                  color: AppTheme.accent,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                          color: AppTheme.surfaceHigh,
                          borderRadius: BorderRadius.circular(99)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RouteStep(
                    active: true,
                    label: 'Picking up from',
                    title: o.merchantName ?? 'Merchant',
                    subtitle: o.merchantAddress,
                  ),
                  const SizedBox(height: 14),
                  _RouteStep(
                    active: false,
                    label: 'Delivering to',
                    title: o.deliveryAddress,
                    subtitle: o.deliveryNotes,
                  ),
                  if (o.specialInstructions != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryFixed,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded,
                              size: 16, color: AppTheme.accent),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(o.specialInstructions!,
                                  style: const TextStyle(fontSize: 12))),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_acting)
                    const Center(
                        child:
                            CircularProgressIndicator(color: AppTheme.accent))
                  else
                    _buildActions(o),
                ],
              ),
            ),
          ),
        ],
    );
  }

  Widget _buildActions(Order o) {
    if (o.isWaitingForShop) {
      return Column(
        children: [
          const Text(
            'The shop is still preparing this order. Head there now; you '
            'can pick it up once it is ready.',
            style: TextStyle(color: AppTheme.mgray),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: () => _navigateTo(context, o.merchantLat, o.merchantLon,
                o.merchantAddress ?? o.merchantName),
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: const Text('Navigate to Merchant'),
          ),
        ],
      );
    }

    if (o.isReadyForPickup) {
      return Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _navigateTo(context, o.merchantLat, o.merchantLon,
                o.merchantAddress ?? o.merchantName),
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: const Text('Navigate to Merchant'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _updateStatus('picked_up'),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Mark Picked Up'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
        ],
      );
    }

    if (o.isPickedUp) {
      return Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => _updateStatus('in_transit'),
            icon: const Icon(Icons.local_shipping_outlined, size: 18),
            label: const Text('Start Delivery'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _navigateTo(context, o.deliveryLatitude,
                o.deliveryLongitude, o.deliveryAddress),
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: const Text('Navigate to Customer'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
        ],
      );
    }

    if (o.isInTransit) {
      return Column(
        children: [
          ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(
                context, '/courier/delivery-proof', arguments: o),
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: const Text('Confirm Delivery'),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.green),
          ),
          const SizedBox(height: 8),
          // Directions are needed most on the way to the customer
          OutlinedButton.icon(
            onPressed: () => _navigateTo(context, o.deliveryLatitude,
                o.deliveryLongitude, o.deliveryAddress),
            icon: const Icon(Icons.navigation_outlined, size: 18),
            label: const Text('Navigate to Customer'),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }
}

class _RouteStep extends StatelessWidget {
  final bool active;
  final String label;
  final String title;
  final String? subtitle;

  const _RouteStep({
    required this.active,
    required this.label,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 12,
          height: 12,
          margin: const EdgeInsets.only(top: 4),
          decoration: BoxDecoration(
            color: active ? AppTheme.accent : Colors.transparent,
            border: Border.all(
                color: active ? AppTheme.accent : AppTheme.mgray, width: 2),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Opacity(
            opacity: active ? 1 : 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(),
                    style: const TextStyle(
                        color: AppTheme.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(title,
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w800)),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: AppTheme.mgray)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetricCard(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppTheme.accent, size: 28),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(color: AppTheme.mgray, fontSize: 12)),
          Text(value,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _VerificationPrompt extends StatelessWidget {
  final CourierProfile profile;

  const _VerificationPrompt({required this.profile});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(
              profile.isPendingReview
                  ? Icons.hourglass_top_outlined
                  : profile.isRejected
                      ? Icons.error_outline
                      : Icons.upload_file_outlined,
              size: 72,
              color: profile.isPendingReview
                  ? AppTheme.gold
                  : profile.isRejected
                      ? AppTheme.accent
                      : AppTheme.mgray,
            ),
            const SizedBox(height: 20),
            Text(
              profile.isPendingReview
                  ? 'Documents Under Review'
                  : profile.isRejected
                      ? 'Application Rejected'
                      : 'Upload Your Documents',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              profile.isPendingReview
                  ? 'Our team is reviewing your documents. You will receive a notification once approved.'
                  : profile.isRejected
                      ? 'Your application was rejected. Please re-upload correct documents.'
                      : 'You need to upload 5 verification documents before you can start delivering.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.mgray),
            ),
            const SizedBox(height: 28),
            if (!profile.isPendingReview)
              ElevatedButton.icon(
                onPressed: () => Navigator.pushNamed(context, '/courier/documents'),
                icon: const Icon(Icons.upload_file_outlined),
                label: Text(profile.isRejected
                    ? 'Re-upload Documents'
                    : 'Upload Documents'),
              ),
          ]),
        ),
      );
}

/// Opens turn-by-turn directions in Google Maps (or the browser).
Future<void> _navigateTo(
    BuildContext context, double? lat, double? lon, String? address) async {
  final destination = lat != null && lon != null ? '$lat,$lon' : address;
  if (destination == null || destination.isEmpty) return;
  final uri = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': destination,
    'travelmode': 'driving',
  });
  final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!opened && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')));
  }
}

// ── Job board: paid orders nobody has taken yet ───────────────────────────────
class _JobBoard extends ConsumerStatefulWidget {
  const _JobBoard({required this.onAccepted});

  final VoidCallback onAccepted;

  @override
  ConsumerState<_JobBoard> createState() => _JobBoardState();
}

class _JobBoardState extends ConsumerState<_JobBoard> {
  Timer? _poll;
  String? _accepting;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(AppConfig.jobsPollInterval, (_) {
      if (mounted) ref.invalidate(availableJobsProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _accept(CourierJob job) async {
    if (_accepting != null) return;
    setState(() => _accepting = job.orderId);
    try {
      await ApiClient.instance.post('/courier/jobs/${job.orderId}/accept');
      widget.onAccepted();
    } catch (e) {
      if (!mounted) return;
      final message = errorCode(e) == 'JOB_TAKEN'
          ? 'Taken by another rider.'
          : errorMessage(e, 'Could not accept this job. Try again.');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      ref.invalidate(availableJobsProvider);
    } finally {
      if (mounted) setState(() => _accepting = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(availableJobsProvider);
    return jobs.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(
          child: CircularProgressIndicator(color: AppTheme.accent)),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(errorMessage(e, 'Could not load jobs.'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppTheme.mgray)),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => ref.invalidate(availableJobsProvider),
              child: const Text('Retry'),
            ),
          ]),
        ),
      ),
      data: (list) {
        if (list.isEmpty) return const _WaitingView(isOnline: true);
        return RefreshIndicator(
          color: AppTheme.accent,
          onRefresh: () => ref.refresh(availableJobsProvider.future),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) {
              if (i == 0) {
                return const Text('Available jobs',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: AppTheme.brand));
              }
              final job = list[i - 1];
              return _JobCard(
                job: job,
                accepting: _accepting == job.orderId,
                onAccept: _accepting == null ? () => _accept(job) : null,
              );
            },
          ),
        );
      },
    );
  }
}

class _JobCard extends StatelessWidget {
  const _JobCard(
      {required this.job, required this.accepting, required this.onAccept});

  final CourierJob job;
  final bool accepting;
  final VoidCallback? onAccept;

  static String _km(double? km) =>
      km == null ? '—' : '${km.toStringAsFixed(1)} km';

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(job.merchantName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ),
              Text('KES ${job.courierPayout.toStringAsFixed(0)}',
                  style: const TextStyle(
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 16)),
            ]),
            const SizedBox(height: 2),
            Text(job.merchantAddress,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppTheme.mgray)),
            const SizedBox(height: 10),
            Wrap(spacing: 16, runSpacing: 4, children: [
              _JobFact(Icons.storefront_outlined,
                  '${_km(job.pickupDistanceKm)} to shop'),
              _JobFact(Icons.flag_outlined,
                  '${_km(job.deliveryDistanceKm)} to customer'),
              _JobFact(Icons.shopping_bag_outlined,
                  '${job.itemCount} item${job.itemCount == 1 ? '' : 's'}'),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onAccept,
                child: accepting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Accept'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JobFact extends StatelessWidget {
  const _JobFact(this.icon, this.label);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: AppTheme.mgray),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.mgray)),
        ],
      );
}
