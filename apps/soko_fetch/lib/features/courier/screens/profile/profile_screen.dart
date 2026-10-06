import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme.dart';
import '../../../../core/session.dart';
import '../../providers/providers.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(courierProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Profile')),
      body: profileAsync.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppTheme.accent)),
        error:   (_, __) => const Center(child: Text('Failed to load profile')),
        data: (profile) => ListView(padding: const EdgeInsets.all(16), children: [
          // Profile card
          Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(children: [
            CircleAvatar(radius: 36,
                backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
                child: const Icon(Icons.delivery_dining, size: 40, color: AppTheme.accent)),
            const SizedBox(height: 12),
            Text(profile.fullName ?? 'Rider',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            _StatusBadge(status: profile.status),
            const SizedBox(height: 14),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _Stat(label: 'Rating', value: profile.rating.toStringAsFixed(1),
                  icon: Icons.star_rounded, color: AppTheme.gold),
              _Stat(label: 'Deliveries', value: '${profile.totalDeliveries}',
                  icon: Icons.local_shipping_outlined, color: AppTheme.accent),
              _Stat(label: 'Total Earned', value: 'KES ${profile.totalEarned.toStringAsFixed(0)}',
                  icon: Icons.payments_outlined, color: AppTheme.teal),
            ]),
          ]))),
          const SizedBox(height: 16),

          // Actions
          Card(child: Column(children: [
            if (!profile.isApproved)
              _Tile(icon: Icons.upload_file_outlined,
                  label: 'Upload Documents',
                  onTap: () => Navigator.pushNamed(context, '/courier/documents')),
            _Tile(icon: Icons.motorcycle_outlined,
                label: 'Vehicle: ${profile.vehicleType.replaceAll('_', ' ')}',
                onTap: () {}),
            if (profile.payoutPhone != null)
              _Tile(icon: Icons.phone_android_outlined,
                  label: 'Payout: ${profile.payoutPhone}',
                  onTap: () {}),
            _Tile(icon: Icons.help_outline, label: 'Help & Support', onTap: () {}),
          ])),
          const SizedBox(height: 16),

          ElevatedButton(
            onPressed: Session.logout,
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accent, minimumSize: const Size.fromHeight(48)),
            child: const Text('Log Out'),
          ),
        ]),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  Color get _color => status == 'active' ? AppTheme.teal
      : status == 'approved' ? AppTheme.gold : AppTheme.mgray;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    decoration: BoxDecoration(color: _color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
    child: Text(status.replaceAll('_', ' ').toUpperCase(),
        style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1)),
  );
}

class _Stat extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Stat({required this.label, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, color: color, size: 20),
    const SizedBox(height: 4),
    Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
    Text(label, style: const TextStyle(color: AppTheme.mgray, fontSize: 11)),
  ]);
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: AppTheme.brand),
    title: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
    trailing: const Icon(Icons.chevron_right, color: AppTheme.mgray),
    onTap: onTap,
  );
}
