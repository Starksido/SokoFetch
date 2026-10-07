import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
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
    return Scaffold(
      backgroundColor: AppTheme.brand,
      body: FadeTransition(
        opacity: _fade,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.delivery_dining,
                    color: Colors.white, size: 48),
              ),
              const SizedBox(height: 24),
              const Text(
                'SOKO FETCH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 6,
                ),
              ),
              const SizedBox(height: 8),
              const Text('On-Demand Delivery',
                  style: TextStyle(color: Colors.white54)),
              const SizedBox(height: 64),
              if (_locked) ...[
                ElevatedButton.icon(
                  onPressed: _unlock,
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Unlock'),
                ),
                const TextButton(
                  onPressed: Session.logout,
                  child: Text('Use another account',
                      style: TextStyle(color: Colors.white70)),
                ),
              ] else
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                      color: AppTheme.accent, strokeWidth: 2.5),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
