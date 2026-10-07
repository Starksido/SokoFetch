import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../../../core/api_client.dart';

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

  /// Sets an item's quantity, adding it if needed (0 removes it).
  void setQuantity(MenuItem item, String merchantId, int qty) {
    if (qty <= 0) return removeItem(item.id);
    if (quantityOf(item.id) == 0) addItem(item, merchantId);
    updateQuantity(item.id, qty);
  }

  /// Replaces the cart, e.g. when reordering.
  void replaceWith(String merchantId, List<CartItem> items) {
    _merchantId = items.isEmpty ? null : merchantId;
    state = items;
  }

  int quantityOf(String itemId) => state
      .where((c) => c.item.id == itemId)
      .fold(0, (sum, c) => sum + c.quantity);

  /// True if adding from [merchantId] would replace another shop's cart.
  bool belongsToOtherShop(String merchantId) =>
      state.isNotEmpty && _merchantId != null && _merchantId != merchantId;

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
  final resp = await ApiClient.instance.get(
    '/merchant/browse',
    params: category != null ? {'category': category} : null,
  );
  final list = resp.data as List<dynamic>;
  return list.map((e) => Merchant.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Single merchant detail + menu ──────────────────────────────────────────────
final merchantDetailProvider = FutureProvider.family<Merchant, String>((ref, merchantId) async {
  final resp = await ApiClient.instance.get('/merchant/$merchantId/menu');
  return Merchant.fromJson(resp.data as Map<String, dynamic>);
});

// ── Orders ─────────────────────────────────────────────────────────────────────
final ordersProvider = FutureProvider<List<OrderSummary>>((ref) async {
  final resp = await ApiClient.instance.get('/orders');
  final list = resp.data as List<dynamic>;
  return list.map((e) => OrderSummary.fromJson(e as Map<String, dynamic>)).toList();
});

final orderDetailProvider = FutureProvider.family<Order, String>((ref, orderId) async {
  final resp = await ApiClient.instance.get('/orders/$orderId');
  return Order.fromJson(resp.data as Map<String, dynamic>);
});

// ── Profile and saved addresses ──────────────────────────────────────────────
final customerProfileProvider = FutureProvider<CustomerProfile>((ref) async {
  final resp = await ApiClient.instance.get('/customer/me');
  return CustomerProfile.fromJson(resp.data as Map<String, dynamic>);
});

final addressesProvider = FutureProvider<List<DeliveryAddress>>((ref) async {
  final resp = await ApiClient.instance.get('/customer/addresses');
  return (resp.data as List<dynamic>)
      .map((e) => DeliveryAddress.fromJson(e as Map<String, dynamic>))
      .toList();
});

/// The address the customer is ordering to. Null: their default (or first).
final selectedAddressIdProvider = StateProvider<String?>((ref) => null);

final selectedAddressProvider = Provider<DeliveryAddress?>((ref) {
  final list = ref.watch(addressesProvider).valueOrNull ?? const [];
  if (list.isEmpty) return null;
  final id = ref.watch(selectedAddressIdProvider);
  return list.firstWhere((a) => a.id == id,
      orElse: () => list.firstWhere((a) => a.isDefault, orElse: () => list.first));
});

