import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../../core/api_client.dart';
import '../../../../core/config.dart';
import '../../../../core/errors.dart';
import '../../../../core/ui/ui.dart';
import '../../models/models.dart';
import '../../providers/providers.dart';

/// Map-first courier home: go online, see jobs, run the active delivery.
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

    Widget panel;
    String? courierId;
    final profile = profileAsync.valueOrNull;
    if (profileAsync.isLoading && profile == null) {
      panel = const _Panel(child: SizedBox(height: 120, child: SfLoader()));
    } else if (profile == null) {
      panel = _Panel(
        child: ErrorState(
            message: "Couldn't load your rider profile.",
            onRetry: () => ref.invalidate(courierProfileProvider)),
      );
    } else if (profile.needsDocs || profile.isPendingReview || profile.isRejected) {
      panel = _VerificationPrompt(profile: profile);
    } else {
      courierId = profile.id;
      final order = activeOrder.valueOrNull;
      if (order != null && order.isActive) {
        _activeOrderId = order.id;
        panel = _ActiveOrderCard(
          order: order,
          onStatusChanged: () {
            ref.invalidate(activeOrderProvider);
            setState(() => _activeOrderId = null);
          },
        );
      } else {
        _activeOrderId = null;
        panel = isOnline
            ? _JobBoard(
                toggling: _toggling,
                onGoOffline: () => _toggleOnline(false, profile.id),
                onAccepted: () => ref.invalidate(activeOrderProvider),
              )
            : _OfflinePanel(
                rating: profile.rating,
                deliveries: profile.totalDeliveries,
                toggling: _toggling,
                onGoOnline: () => _toggleOnline(true, profile.id),
              );
      }
    }

    return Scaffold(
      body: Stack(children: [
        Positioned.fill(
          child: AppConfig.mapsEnabled
              ? GoogleMap(
                  initialCameraPosition: const CameraPosition(
                      target: LatLng(-1.2921, 36.8219), zoom: 13),
                  myLocationEnabled: isOnline,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                )
              : const MapPlaceholder(icon: Icons.delivery_dining_rounded),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(SfSpace.sm),
            child: Row(children: [
              SfCircleButton(
                icon: Icons.person_outline_rounded,
                tooltip: 'Profile',
                onPressed: widget.onOpenProfile,
              ),
              const Spacer(),
              const _EarningsPill(),
              const Spacer(),
              _OnlineDot(online: isOnline && courierId != null),
            ]),
          ),
        ),
        panel,
      ]),
    );
  }
}

/// Today's earnings, centred at the top of the map.
class _EarningsPill extends ConsumerWidget {
  const _EarningsPill();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = ref.watch(earningsProvider).valueOrNull;
    final earned = today == null ? null : parseNum(today['earned']);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: SfSpace.md, vertical: 10),
      decoration: const BoxDecoration(
        color: SfColors.ink,
        borderRadius: SfRadius.pillAll,
        boxShadow: SfShadow.floating,
      ),
      child: Text(
        earned == null ? 'Today' : formatKes(earned),
        style: Theme.of(context)
            .textTheme
            .labelLarge!
            .copyWith(color: Colors.white),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) => Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
            color: SfColors.surface, shape: BoxShape.circle),
        child: Center(
          child: Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: online ? SfColors.success : SfColors.inkFaint,
              shape: BoxShape.circle,
            ),
          ),
        ),
      );
}

/// White panel docked to the bottom of the map.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.bottomCenter,
        child: MaxWidth(
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: SfColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(SfRadius.lg)),
              boxShadow: SfShadow.floating,
            ),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.all(SfSpace.md),
              child: child,
            ),
          ),
        ),
      );
}

/// A draggable sheet with a scrollable body (jobs, active delivery).
class _Sheet extends StatelessWidget {
  const _Sheet({required this.children, this.initial = 0.5});
  final List<Widget> children;
  final double initial;

  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
        initialChildSize: initial,
        minChildSize: 0.25,
        maxChildSize: 0.92,
        builder: (context, scroll) => MaxWidth(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              color: SfColors.surface,
              borderRadius:
                  BorderRadius.vertical(top: Radius.circular(SfRadius.lg)),
              boxShadow: SfShadow.floating,
            ),
            child: ListView(
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
                        color: SfColors.surface3, borderRadius: SfRadius.pillAll),
                  ),
                ),
                ...children,
              ],
            ),
          ),
        ),
      );
}

class _OfflinePanel extends StatelessWidget {
  const _OfflinePanel({required this.rating, required this.deliveries,
      required this.toggling, required this.onGoOnline});

  final double rating;
  final int deliveries;
  final bool toggling;
  final VoidCallback onGoOnline;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Big round Go button above the panel
        Semantics(
          button: true,
          label: 'Go online',
          child: Material(
            color: SfColors.brand,
            shape: const CircleBorder(),
            elevation: 6,
            shadowColor: const Color(0x55F26B1D),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: toggling ? null : onGoOnline,
              child: SizedBox(
                width: 96,
                height: 96,
                child: Center(
                  child: toggling
                      ? const SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 3))
                      : Text('GO',
                          style: text.headlineSmall!.copyWith(
                              color: Colors.white, letterSpacing: 1)),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: SfSpace.md),
        _Panel(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text("You're offline", style: text.titleLarge),
            const SizedBox(height: SfSpace.xxs),
            Text('Go online to see delivery jobs near you.',
                style: text.bodyMedium, textAlign: TextAlign.center),
            const SizedBox(height: SfSpace.md),
            Row(children: [
              Expanded(
                child: StatTile(
                    label: 'Rating',
                    value: rating.toStringAsFixed(1),
                    icon: Icons.star_rounded),
              ),
              const SizedBox(width: SfSpace.sm),
              Expanded(
                child: StatTile(
                    label: 'Deliveries',
                    value: '$deliveries',
                    icon: Icons.local_shipping_outlined),
              ),
            ]),
          ]),
        ),
      ]),
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(errorMessage(e, "Couldn't update the order."))));
      }
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  (String, String) get _step {
    final o = widget.order;
    final shop = o.merchantName ?? 'the shop';
    if (o.isWaitingForShop) return ('Head to $shop', 'The shop is still preparing this order');
    if (o.isReadyForPickup) return ('Pick up at $shop', 'The order is ready');
    if (o.isPickedUp) return ('Order picked up', 'Start the delivery when you leave');
    return ('Deliver to the customer', 'Get the 4-digit code when you hand it over');
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.order;
    final (title, subtitle) = _step;
    final pickupDone = o.isPickedUp || o.isInTransit;

    return _Sheet(initial: 0.55, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.headlineSmall),
            const SizedBox(height: 2),
            Text(subtitle, style: text.bodyMedium),
          ]),
        ),
        const SizedBox(width: SfSpace.sm),
        StatusPill(formatKes(o.courierPayout), tone: PillTone.accent),
      ]),
      const SizedBox(height: SfSpace.lg),
      _RouteStep(
        done: pickupDone,
        active: !pickupDone,
        label: 'Pick up',
        title: o.merchantName ?? 'Shop',
        subtitle: o.merchantAddress,
        showLine: true,
      ),
      _RouteStep(
        done: false,
        active: pickupDone,
        label: 'Drop off',
        title: o.deliveryAddress,
        subtitle: o.deliveryNotes,
      ),
      if (o.specialInstructions != null) ...[
        const SizedBox(height: SfSpace.sm),
        InlineMessage(o.specialInstructions!, isError: false),
      ],
      const SizedBox(height: SfSpace.lg),
      if (_acting) const SfLoader() else _buildActions(o),
    ]);
  }

  Widget _buildActions(Order o) {
    void toShop() => _navigateTo(
        context, o.merchantLat, o.merchantLon, o.merchantAddress ?? o.merchantName);
    void toCustomer() => _navigateTo(
        context, o.deliveryLatitude, o.deliveryLongitude, o.deliveryAddress);

    Widget pair(Widget main, Widget other) => Column(children: [
          main,
          const SizedBox(height: SfSpace.xs),
          other,
        ]);

    if (o.isWaitingForShop) {
      return SfButton.primary(
          label: 'Navigate to Merchant',
          icon: Icons.navigation_outlined,
          onPressed: toShop);
    }
    if (o.isReadyForPickup) {
      return pair(
        SfButton.primary(
            label: 'Mark Picked Up',
            icon: Icons.check_rounded,
            onPressed: () => _updateStatus('picked_up')),
        SfButton.secondary(
            label: 'Navigate to Merchant',
            icon: Icons.navigation_outlined,
            onPressed: toShop),
      );
    }
    if (o.isPickedUp) {
      return pair(
        SfButton.primary(
            label: 'Start Delivery',
            icon: Icons.local_shipping_outlined,
            onPressed: () => _updateStatus('in_transit')),
        SfButton.secondary(
            label: 'Navigate to Customer',
            icon: Icons.navigation_outlined,
            onPressed: toCustomer),
      );
    }
    if (o.isInTransit) {
      return pair(
        SfButton.primary(
            label: 'Confirm Delivery',
            icon: Icons.check_circle_outline,
            onPressed: () => Navigator.pushNamed(
                context, '/courier/delivery-proof', arguments: o)),
        // Directions are needed most on the way to the customer
        SfButton.secondary(
            label: 'Navigate to Customer',
            icon: Icons.navigation_outlined,
            onPressed: toCustomer),
      );
    }
    return const SizedBox.shrink();
  }
}

/// A stop on the route: a dot (filled when current, ticked when done) and a
/// line down to the next stop.
class _RouteStep extends StatelessWidget {
  const _RouteStep({required this.done, required this.active,
      required this.label, required this.title, this.subtitle,
      this.showLine = false});

  final bool done;
  final bool active;
  final String label;
  final String title;
  final String? subtitle;
  final bool showLine;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = done || active ? SfColors.brand : SfColors.surface3;
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          width: 24,
          child: Column(children: [
            Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color: done ? SfColors.brand : SfColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: color, width: 3),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 11, color: Colors.white)
                  : null,
            ),
            if (showLine)
              Expanded(
                child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    color: SfColors.surface3),
              ),
          ]),
        ),
        const SizedBox(width: SfSpace.sm),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(bottom: showLine ? SfSpace.md : 0),
            child: Opacity(
              opacity: done ? 0.55 : 1,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label.toUpperCase(),
                    style: text.labelSmall!.copyWith(color: SfColors.accentStrong)),
                const SizedBox(height: 2),
                Text(title, style: text.titleSmall),
                if (subtitle != null)
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}

class _VerificationPrompt extends StatelessWidget {
  final CourierProfile profile;

  const _VerificationPrompt({required this.profile});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final (icon, title, message) = profile.isPendingReview
        ? (
            Icons.hourglass_top_rounded,
            'Documents under review',
            "We're checking your documents. You can start delivering once you're approved."
          )
        : profile.isRejected
            ? (
                Icons.error_outline_rounded,
                'Application not approved',
                'Please re-upload clear photos of your documents.'
              )
            : (
                Icons.upload_file_outlined,
                'Upload your documents',
                'Upload 5 verification documents before you can start delivering.'
              );
    return _Panel(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64,
          height: 64,
          decoration: const BoxDecoration(
              color: SfColors.surface2, shape: BoxShape.circle),
          child: Icon(icon,
              size: 30,
              color: profile.isRejected ? SfColors.danger : SfColors.accentStrong),
        ),
        const SizedBox(height: SfSpace.md),
        Text(title, style: text.titleLarge, textAlign: TextAlign.center),
        const SizedBox(height: SfSpace.xxs),
        Text(message, style: text.bodyMedium, textAlign: TextAlign.center),
        if (!profile.isPendingReview) ...[
          const SizedBox(height: SfSpace.lg),
          SfButton.primary(
            label: profile.isRejected ? 'Re-upload documents' : 'Upload documents',
            icon: Icons.upload_file_outlined,
            onPressed: () => Navigator.pushNamed(context, '/courier/documents'),
          ),
        ],
      ]),
    );
  }
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
  const _JobBoard({required this.onAccepted, required this.onGoOffline,
      required this.toggling});

  final VoidCallback onAccepted;
  final VoidCallback onGoOffline;
  final bool toggling;

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
    final text = Theme.of(context).textTheme;
    final jobs = ref.watch(availableJobsProvider);
    final count = jobs.valueOrNull?.length ?? 0;

    return _Sheet(initial: 0.45, children: [
      Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text("You're online", style: text.titleLarge),
            Text(
                count == 0
                    ? 'Looking for jobs near you'
                    : '$count job${count == 1 ? '' : 's'} available',
                style: text.bodyMedium),
          ]),
        ),
        SfButton.text(
          label: 'Go offline',
          loading: widget.toggling,
          onPressed: widget.onGoOffline,
        ),
      ]),
      const SizedBox(height: SfSpace.sm),
      const ClipRRect(
          borderRadius: SfRadius.pillAll,
          child: LinearProgressIndicator(minHeight: 3)),
      const SizedBox(height: SfSpace.md),
      ...jobs.when(
        skipLoadingOnRefresh: true,
        loading: () => [const LoadingList(count: 2)],
        error: (e, _) => [
          ErrorState(
            message: errorMessage(e, 'Could not load jobs.'),
            onRetry: () => ref.invalidate(availableJobsProvider),
          ),
        ],
        data: (list) => list.isEmpty
            ? [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: SfSpace.lg),
                  child: Text(
                    'No jobs right now. Keep the app open; new ones appear here.',
                    style: text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ]
            : [
                for (final job in list) ...[
                  _JobCard(
                    job: job,
                    accepting: _accepting == job.orderId,
                    onAccept: _accepting == null ? () => _accept(job) : null,
                  ),
                  const SizedBox(height: SfSpace.sm),
                ],
              ],
      ),
    ]);
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
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(SfSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(job.merchantName,
                      style: text.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text(job.merchantAddress,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium),
                ]),
              ),
              const SizedBox(width: SfSpace.sm),
              Text(formatKes(job.courierPayout),
                  style: text.titleLarge!.copyWith(color: SfColors.accentStrong)),
            ]),
            const SizedBox(height: SfSpace.sm),
            Wrap(spacing: SfSpace.xs, runSpacing: SfSpace.xs, children: [
              StatusPill('${_km(job.pickupDistanceKm)} to shop',
                  icon: Icons.storefront_outlined),
              StatusPill('${_km(job.deliveryDistanceKm)} to customer',
                  icon: Icons.flag_outlined),
              StatusPill('${job.itemCount} item${job.itemCount == 1 ? '' : 's'}',
                  icon: Icons.shopping_bag_outlined),
            ]),
            const SizedBox(height: SfSpace.md),
            SfButton.primary(label: 'Accept', loading: accepting, onPressed: onAccept),
          ],
        ),
      ),
    );
  }
}
