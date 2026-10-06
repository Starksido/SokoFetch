import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../../core/api_client.dart';

// ── Online status ─────────────────────────────────────────────────────────────
class OnlineNotifier extends StateNotifier<bool> {
  OnlineNotifier() : super(false);
  void set(bool v) => state = v;
}
final onlineProvider = StateNotifierProvider<OnlineNotifier, bool>((ref) => OnlineNotifier());

// ── Courier profile ───────────────────────────────────────────────────────────
final courierProfileProvider = FutureProvider<CourierProfile>((ref) async {
  final resp = await ApiClient.instance.get('/courier/me');
  return CourierProfile.fromJson(resp.data as Map<String, dynamic>);
});

// ── Active order ──────────────────────────────────────────────────────────────
final activeOrderProvider = FutureProvider<Order?>((ref) async {
  try {
    final resp = await ApiClient.instance.get('/courier/order/active');
    if (resp.data == null) return null;
    return Order.fromJson(resp.data as Map<String, dynamic>);
  } catch (_) { return null; }
});

// ── Available jobs ────────────────────────────────────────────────────────────
// Errors surface on the job board (e.g. OFFLINE, not approved), so no catch here
final availableJobsProvider = FutureProvider.autoDispose<List<CourierJob>>((ref) async {
  final resp = await ApiClient.instance.get('/courier/jobs');
  final list = resp.data as List<dynamic>;
  return list.map((e) => CourierJob.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Earnings ──────────────────────────────────────────────────────────────────
final earningsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final resp = await ApiClient.instance.get('/payments/earnings/courier');
  return resp.data as Map<String, dynamic>;
});

final earningsHistoryProvider = FutureProvider<List<EarningsDay>>((ref) async {
  final resp = await ApiClient.instance.get('/courier/earnings', params: {'days': 14});
  final list = resp.data as List<dynamic>;
  return list.map((e) => EarningsDay.fromJson(e as Map<String, dynamic>)).toList();
});
