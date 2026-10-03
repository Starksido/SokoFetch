import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/app_theme.dart';
import '../../network/api_client.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(merchantProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Shop Profile')),
      body: profileAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error: (_, __) => Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Text('Failed to load profile'),
            const SizedBox(height: 12),
            ElevatedButton(
                onPressed: () => ref.invalidate(merchantProfileProvider),
                child: const Text('Retry')),
          ]),
        ),
        data: (profile) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Status card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: AppTheme.accent.withOpacity(0.12),
                          child: const Icon(Icons.storefront_outlined,
                              size: 32, color: AppTheme.accent),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(profile.shopName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17)),
                                Text(profile.category,
                                    style: const TextStyle(
                                        color: AppTheme.mgray, fontSize: 13)),
                              ]),
                        ),
                        _StatusBadge(status: profile.status),
                      ]),
                      const SizedBox(height: 16),
                      _InfoRow(
                          icon: Icons.location_on_outlined,
                          label: 'Address',
                          value: profile.address),
                      _InfoRow(
                          icon: Icons.star_rounded,
                          label: 'Rating',
                          value:
                              '${profile.rating.toStringAsFixed(1)} (${profile.ratingCount} reviews)'),
                      _InfoRow(
                          icon: Icons.percent_outlined,
                          label: 'Commission rate',
                          value: '${profile.commissionRate.toStringAsFixed(0)}%'),
                      if (profile.payoutPhone != null)
                        _InfoRow(
                            icon: Icons.phone_android_outlined,
                            label: 'Payout M-Pesa',
                            value: profile.payoutPhone!),
                    ]),
              ),
            ),
            const SizedBox(height: 16),

            // Quick actions
            Card(
              child: Column(children: [
                _ActionTile(
                  icon: Icons.edit_outlined,
                  label: 'Edit Shop Details',
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                _ActionTile(
                  icon: Icons.schedule_outlined,
                  label: 'Operating Hours',
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                _ActionTile(
                  icon: Icons.account_balance_wallet_outlined,
                  label: 'Payout Details',
                  onTap: () {},
                ),
                const Divider(height: 1, indent: 56),
                _ActionTile(
                  icon: Icons.help_outline,
                  label: 'Help & Support',
                  onTap: () {},
                ),
              ]),
            ),
            const SizedBox(height: 16),

            // Pending notice
            if (profile.isPending)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.gold.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withOpacity(0.3)),
                ),
                child: const Row(children: [
                  Icon(Icons.access_time_outlined, color: AppTheme.gold),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Your shop is pending review. Our team will approve your account within 24 hours.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ]),
              ),

            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await ApiClient.instance.post('/auth/logout');
                await ApiClient.clearTokens();
                if (!context.mounted) return;
                ref.read(authProvider.notifier).clear();
                Navigator.pushNamedAndRemoveUntil(
                    context, '/auth/phone', (_) => false);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.red,
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Log Out'),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? AppTheme.green : AppTheme.gold).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(
          color: isActive ? AppTheme.green : AppTheme.gold,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _InfoRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Icon(icon, size: 18, color: AppTheme.mgray),
          const SizedBox(width: 10),
          Text('$label: ',
              style: const TextStyle(color: AppTheme.mgray, fontSize: 13)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontWeight: FontWeight.w500, fontSize: 13))),
        ]),
      );
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionTile(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppTheme.brand),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        trailing: const Icon(Icons.chevron_right, color: AppTheme.mgray),
        onTap: onTap,
      );
}

