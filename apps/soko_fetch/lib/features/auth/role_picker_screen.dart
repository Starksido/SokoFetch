import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors.dart';
import '../../core/session.dart';
import '../../core/ui/ui.dart';
import 'auth_service.dart';

class _RoleOption {
  const _RoleOption(this.role, this.title, this.subtitle, this.icon);
  final String role, title, subtitle;
  final IconData icon;
}

const _options = [
  _RoleOption('customer', 'Customer',
      'Order groceries, food and more from shops near you',
      Icons.shopping_bag_outlined),
  _RoleOption('merchant', 'Merchant',
      'Sell from your shop and get orders delivered',
      Icons.storefront_outlined),
  _RoleOption('courier', 'Courier',
      'Deliver orders and earn on your own schedule',
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
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(),
      // The error sits above the button so it's always on screen
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
                SfSpace.md, SfSpace.xs, SfSpace.md, 0),
            child: InlineMessage(_error!),
          ),
        if (_expired)
          SafeArea(
            minimum: const EdgeInsets.all(SfSpace.md),
            child: SfButton.outline(
              label: 'Start again',
              onPressed: () => Navigator.of(context)
                  .pushNamedAndRemoveUntil('/welcome', (_) => false),
            ),
          )
        else
          BottomCtaBar(
            label: 'Continue',
            loading: _loading,
            onPressed: _selected == null ? null : _continue,
          ),
      ]),
      body: SafeArea(
        child: MaxWidth(
          maxWidth: 560,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
                SfSpace.lg, SfSpace.xs, SfSpace.lg, SfSpace.lg),
            children: [
              Text('How will you use\nSoko Fetch?', style: text.headlineMedium),
              const SizedBox(height: SfSpace.xs),
              Text(
                "You can't change this later. To use another role, sign up "
                'with a different phone number or Google account.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: SfSpace.lg),
              for (final o in _options) ...[
                _RoleCard(
                  option: o,
                  selected: _selected == o.role,
                  onTap: _loading || _expired
                      ? null
                      : () => setState(() => _selected = o.role),
                ),
                const SizedBox(height: SfSpace.sm),
              ],
            ],
          ),
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
    final text = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? SfColors.surface2 : SfColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: SfRadius.mdAll,
          side: BorderSide(
              color: selected ? SfColors.ink : SfColors.surface3,
              width: selected ? 2 : 1),
        ),
        child: InkWell(
          borderRadius: SfRadius.mdAll,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(SfSpace.md),
            child: Row(children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: selected ? SfColors.ink : SfColors.surface2,
                  shape: BoxShape.circle,
                ),
                child: Icon(option.icon,
                    color: selected ? Colors.white : SfColors.ink),
              ),
              const SizedBox(width: SfSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(option.title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(option.subtitle, style: text.bodyMedium),
                  ],
                ),
              ),
              const SizedBox(width: SfSpace.xs),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? SfColors.ink : SfColors.surface3,
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
