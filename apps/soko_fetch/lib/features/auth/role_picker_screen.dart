import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/session.dart';
import '../../core/theme.dart';
import 'auth_service.dart';
import 'welcome_screen.dart' show ErrorBanner;

class _RoleOption {
  const _RoleOption(this.role, this.title, this.subtitle, this.icon);
  final String role, title, subtitle;
  final IconData icon;
}

const _options = [
  _RoleOption('customer', 'Customer', 'Order from local shops',
      Icons.shopping_bag_outlined),
  _RoleOption('merchant', 'Merchant', 'Sell from your shop',
      Icons.storefront_outlined),
  _RoleOption('courier', 'Courier', 'Deliver and earn',
      Icons.delivery_dining_outlined),
];

/// Shown once, to new users, after their phone or Google account is
/// verified. The account is created with the chosen role, which can't be
/// changed later.
class RolePickerScreen extends ConsumerStatefulWidget {
  const RolePickerScreen({super.key});

  @override
  ConsumerState<RolePickerScreen> createState() => _RolePickerScreenState();
}

class _RolePickerScreenState extends ConsumerState<RolePickerScreen> {
  String? _selected;
  bool _loading = false;
  String? _error;
  bool _expired = false;

  Future<void> _continue() async {
    final role = _selected;
    if (role == null) return;
    final token = ModalRoute.of(context)!.settings.arguments as String;

    setState(() { _loading = true; _error = null; });
    try {
      final user = await AuthService.instance.signup(token, role);
      ref.read(currentUserProvider.notifier).state = user;
      if (!mounted) return;
      // A brand-new account has no profile yet
      Navigator.of(context)
          .pushNamedAndRemoveUntil('/$role/onboarding', (_) => false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (errorCode(e) == 'INVALID_SIGNUP_TOKEN') {
          _expired = true;
          _error = 'This took too long. Please verify your phone or Google account again.';
        } else {
          _error = errorMessage(e, 'Could not create your account. Please try again.');
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        title: const Text('Create your account'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text('How will you use Soko Fetch?',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.brand)),
            const SizedBox(height: 8),
            const Text(
              "You can't change this later. To use another role, sign up "
              'with a different phone number or Google account.',
              style: TextStyle(color: AppTheme.mgray),
            ),
            const SizedBox(height: 24),
            for (final o in _options) ...[
              _RoleCard(
                option: o,
                selected: _selected == o.role,
                onTap: _loading || _expired
                    ? null
                    : () => setState(() => _selected = o.role),
              ),
              const SizedBox(height: 12),
            ],
            if (_error != null) ...[
              const SizedBox(height: 4),
              ErrorBanner(_error!),
            ],
            const SizedBox(height: 20),
            if (_expired)
              OutlinedButton(
                onPressed: () => Navigator.of(context)
                    .pushNamedAndRemoveUntil('/welcome', (_) => false),
                style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: const Text('Start again'),
              )
            else
              ElevatedButton(
                onPressed: _selected == null || _loading ? null : _continue,
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52)),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : const Text('Continue'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard(
      {required this.option, required this.selected, required this.onTap});

  final _RoleOption option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppTheme.accent : AppTheme.outlineVariant;
    return Material(
      color: selected
          ? AppTheme.accent.withValues(alpha: 0.06)
          : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: color, width: selected ? 2 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
              child: Icon(option.icon, color: AppTheme.accent),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.title,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(option.subtitle,
                      style: const TextStyle(color: AppTheme.mgray)),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? AppTheme.accent : AppTheme.mgray,
            ),
          ]),
        ),
      ),
    );
  }
}
