import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../auth/auth_service.dart';
import '../network/secure_client.dart';

// ── Auth state ─────────────────────────────────────────────────────────────────
class AuthNotifier extends StateNotifier<UserProfile?> {
  AuthNotifier() : super(null);

  void setUser(UserProfile user) => state = user;
  void clearUser()               => state = null;
}

final authProvider = StateNotifierProvider<AuthNotifier, UserProfile?>(
  (ref) => AuthNotifier(),
);

// ── Cart state ─────────────────────────────────────────────────────────────────
class CartNotifier extends StateNotifier<List<CartItem>> {
  CartNotifier() : super([]);

  String? _merchantId;
  String? get merchantId => _merchantId;

  void addItem(MenuItem item, String merchantId) {
    // Clear cart if switching merchants
    if (_merchantId != null && _merchantId != merchantId) {
      state = [];
    }
    _merchantId = merchantId;

    final idx = state.indexWhere((c) => c.item.id == item.id);
    if (idx >= 0) {
      state = [
        for (int i = 0; i < state.length; i++)
          if (i == idx)
            CartItem(item: state[i].item, quantity: state[i].quantity + 1)
          else
            state[i],
      ];
    } else {
      state = [...state, CartItem(item: item)];
    }
  }

  void removeItem(String itemId) {
    state = state.where((c) => c.item.id != itemId).toList();
    if (state.isEmpty) _merchantId = null;
  }

  void updateQuantity(String itemId, int qty) {
    if (qty <= 0) {
      removeItem(itemId);
      return;
    }
    state = [
      for (final c in state)
        if (c.item.id == itemId) CartItem(item: c.item, quantity: qty) else c,
    ];
  }

  void clear() {
    state      = [];
    _merchantId = null;
  }

  double get subtotal =>
      state.fold(0.0, (sum, c) => sum + c.lineTotal);

  int get totalItems =>
      state.fold(0, (sum, c) => sum + c.quantity);
}

final cartProvider = StateNotifierProvider<CartNotifier, List<CartItem>>(
  (ref) => CartNotifier(),
);

// ── Merchants list ─────────────────────────────────────────────────────────────
final merchantsProvider = FutureProvider.family<List<Merchant>, String?>((ref, category) async {
  final resp = await SecureApiClient.instance.get(
    '/merchant/browse',
    params: category != null ? {'category': category} : null,
  );
  final list = resp.data as List<dynamic>;
  return list.map((e) => Merchant.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Single merchant detail + menu ──────────────────────────────────────────────
final merchantDetailProvider = FutureProvider.family<Merchant, String>((ref, merchantId) async {
  final resp = await SecureApiClient.instance.get('/merchant/$merchantId/menu');
  return Merchant.fromJson(resp.data as Map<String, dynamic>);
});

// ── Orders ─────────────────────────────────────────────────────────────────────
final ordersProvider = FutureProvider<List<Order>>((ref) async {
  final resp = await SecureApiClient.instance.get('/orders');
  final list = resp.data as List<dynamic>;
  return list.map((e) => Order.fromJson(e as Map<String, dynamic>)).toList();
});

final orderDetailProvider = FutureProvider.family<Order, String>((ref, orderId) async {
  final resp = await SecureApiClient.instance.get('/orders/$orderId');
  return Order.fromJson(resp.data as Map<String, dynamic>);
});
