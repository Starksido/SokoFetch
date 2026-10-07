import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/ui/ui.dart';
import 'auth_service.dart';

/// Decides where the app opens: the welcome screen, or the signed-in
/// user's area (after a device unlock for customers who have one set up).
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.delay = const Duration(milliseconds: 1200)});

  final Duration delay;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))
    ..forward();
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeIn);

  String? _role;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    await Future.delayed(widget.delay);
    if (!await Session.hasSession) return _go('/welcome');

    _role = await Session.role;
    // Anything else (e.g. an admin session from before the admin panel was
    // split out) can't be used here
    if (!kSignupRoles.contains(_role)) return Session.logout();

    if (_role == 'customer' && await AuthService.instance.canUseDeviceLock()) {
      return _unlock();
    }
    await _enter();
  }

  Future<void> _unlock() async {
    setState(() => _locked = false);
    if (await AuthService.instance.unlockWithDeviceLock()) {
      await _enter();
    } else if (mounted) {
      setState(() => _locked = true);
    }
  }

  Future<void> _enter() async {
    final role = _role!;
    String destination;
    try {
      destination = await AuthService.instance.landingRoute(role);
    } catch (_) {
      destination = AuthService.homeRoute(role); // Offline etc. — screens show their own errors
    }
    _go(destination);
  }

  void _go(String route) {
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      backgroundColor: SfColors.accent,
      body: FadeTransition(
        opacity: _fade,
        child: SafeArea(
          child: Column(
            children: [
              const Spacer(),
              const SokoMark(size: 88, inverted: true),
              const SizedBox(height: SfSpace.lg),
              const SokoWordmark(color: Colors.white, size: 30),
              const SizedBox(height: SfSpace.xs),
              Text('Your local shops, delivered',
                  style: text.bodyLarge!.copyWith(color: Colors.white)),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.all(SfSpace.lg),
                child: _locked
                    ? Column(children: [
                        SfButton.primary(
                          label: 'Unlock',
                          icon: Icons.lock_open_rounded,
                          onPressed: _unlock,
                        ),
                        const SizedBox(height: SfSpace.xs),
                        TextButton(
                          onPressed: Session.logout,
                          style: TextButton.styleFrom(
                              foregroundColor: Colors.white),
                          child: const Text('Use another account'),
                        ),
                      ])
                    : const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
