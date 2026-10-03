import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../network/api_client.dart';

// ── Auth ───────────────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<UserProfile?> {
  AuthNotifier() : super(null);
  void setUser(UserProfile u) => state = u;
  void clear()                => state = null;
}

final authProvider =
    StateNotifierProvider<AuthNotifier, UserProfile?>((ref) => AuthNotifier());

// ── Merchant profile ──────────────────────────────────────────────────────────
final merchantProfileProvider = FutureProvider<MerchantProfile>((ref) async {
  final resp = await ApiClient.instance.get('/merchant/me');
  return MerchantProfile.fromJson(resp.data as Map<String, dynamic>);
});

// ── Live orders ───────────────────────────────────────────────────────────────
final liveOrdersProvider = FutureProvider<List<Order>>((ref) async {
  final resp = await ApiClient.instance.get('/merchant/orders/live');
  final list = resp.data as List<dynamic>;
  return list
      .map((e) => Order.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Menu items ────────────────────────────────────────────────────────────────
final menuProvider = FutureProvider<List<MenuItem>>((ref) async {
  final resp = await ApiClient.instance.get('/merchant/menu');
  final list = resp.data as List<dynamic>;
  return list
      .map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Earnings ──────────────────────────────────────────────────────────────────
final todayEarningsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resp = await ApiClient.instance.get('/payments/earnings/merchant');
  return resp.data as Map<String, dynamic>;
});

final weeklyEarningsProvider = FutureProvider<List<DailyEarnings>>((ref) async {
  final resp = await ApiClient.instance.get('/merchant/earnings/weekly');
  final list = resp.data as List<dynamic>;
  return list
      .map((e) => DailyEarnings.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ── Order count badge for nav ─────────────────────────────────────────────────
final pendingOrderCountProvider = Provider<int>((ref) {
  return ref.watch(liveOrdersProvider).when(
    data: (orders) => orders.where((o) => o.isPending).length,
    loading: () => 0,
    error: (_, __) => 0,
  );
});
