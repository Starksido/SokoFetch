import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/theme.dart';
import '../../../../core/session.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Avatar
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: AppTheme.accent.withValues(alpha: 0.12),
              child: const Icon(Icons.person_outline,
                  size: 48, color: AppTheme.accent),
            ),
          ),
          const SizedBox(height: 12),
          if (user != null) ...[
            Center(
              child: Text(user.phone ?? user.email ?? 'No contact info',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ),
            const SizedBox(height: 4),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: AppTheme.teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(user.role.toUpperCase(),
                    style: const TextStyle(
                        color: AppTheme.teal,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
              ),
            ),
          ],
          const SizedBox(height: 32),
          // Menu items
          _ProfileTile(
            icon: Icons.receipt_long_outlined,
            label: 'Order History',
            onTap: () => Navigator.pushNamed(context, '/customer/orders'),
          ),
          _ProfileTile(
            icon: Icons.location_on_outlined,
            label: 'Saved Addresses',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.notifications_outlined,
            label: 'Notifications',
            onTap: () {},
          ),
          _ProfileTile(
            icon: Icons.help_outline,
            label: 'Help & Support',
            onTap: () {},
          ),
          const SizedBox(height: 8),
          const Divider(),
          const SizedBox(height: 8),
          _ProfileTile(
            icon: Icons.logout,
            label: 'Log Out',
            color: AppTheme.accent,
            onTap: Session.logout,
          ),
        ],
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ProfileTile(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.color});

  @override
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: color ?? AppTheme.brand),
        title: Text(label,
            style: TextStyle(
                color: color ?? AppTheme.brand,
                fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.chevron_right,
            color: color ?? AppTheme.mgray),
        onTap: onTap,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      );
}
