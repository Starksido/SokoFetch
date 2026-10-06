import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../courier/models/models.dart' show CourierProfile;

/// A shop waiting for approval (GET /admin/merchants).
class PendingShop {
  final String id, shopName, category, address, city, status;
  final String? description, payoutPhone;
  final DateTime createdAt;

  const PendingShop({
    required this.id,
    required this.shopName,
    required this.category,
    required this.address,
    required this.city,
    required this.status,
    this.description,
    this.payoutPhone,
    required this.createdAt,
  });

  factory PendingShop.fromJson(Map<String, dynamic> j) => PendingShop(
        id: j['id'] as String,
        shopName: j['shop_name'] as String,
        category: j['category'] as String,
        address: j['address'] as String,
        city: j['city'] as String? ?? '',
        status: j['status'] as String,
        description: j['description'] as String?,
        payoutPhone: j['payout_phone'] as String?,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

/// A rider as the admin reviews them.
class RiderReview {
  const RiderReview(this.profile, this.rejectionReason, this.createdAt);
  final CourierProfile profile;
  final String? rejectionReason;
  final DateTime createdAt;

  factory RiderReview.fromJson(Map<String, dynamic> j) => RiderReview(
        CourierProfile.fromJson(j),
        j['rejection_reason'] as String?,
        DateTime.parse(j['created_at'] as String),
      );
}

ApiClient get _api => ApiClient.instance;

final pendingShopsProvider =
    FutureProvider.autoDispose<List<PendingShop>>((ref) async {
  final resp = await _api.get('/admin/merchants');
  return (resp.data as List)
      .map((e) => PendingShop.fromJson(e as Map<String, dynamic>))
      .toList();
});

final pendingRidersProvider =
    FutureProvider.autoDispose<List<RiderReview>>((ref) async {
  final resp = await _api.get('/admin/couriers');
  return (resp.data as List)
      .map((e) => RiderReview.fromJson(e as Map<String, dynamic>))
      .toList();
});

final riderProvider =
    FutureProvider.autoDispose.family<RiderReview, String>((ref, id) async {
  final resp = await _api.get('/admin/couriers/$id');
  return RiderReview.fromJson(resp.data as Map<String, dynamic>);
});

/// Documents are stored encrypted, so the server decrypts and streams them;
/// they need the admin's token, hence bytes instead of an image URL.
final riderDocumentProvider = FutureProvider.autoDispose
    .family<List<int>, ({String courierId, String docType})>((ref, key) =>
        _api.getBytes(
            '/admin/couriers/${key.courierId}/documents/${key.docType}'));

class AdminApi {
  AdminApi._();

  static Future<void> approveShop(String id) =>
      _api.post('/admin/merchants/$id/approve');

  static Future<void> rejectShop(String id, String reason) =>
      _api.post('/admin/merchants/$id/reject', data: {'reason': reason});

  static Future<void> approveRider(String id) =>
      _api.post('/admin/couriers/$id/approve');

  static Future<void> rejectRider(String id, String reason) =>
      _api.post('/admin/couriers/$id/reject', data: {'reason': reason});
}

String formatDate(DateTime d) {
  final l = d.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}
