import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;

import '../../../core/models.dart';

export '../../../core/models.dart';

// ── Merchant ──────────────────────────────────────────────────────────────────
class Merchant {
  final String id;
  final String shopName;
  final String category;
  final String? logoUrl;
  final String? bannerUrl;
  final String address;
  final double? latitude;
  final double? longitude;
  final double rating;
  final int ratingCount;
  final int avgPrepMinutes;
  final double minOrderAmount;
  final bool isOpen;
  final String status;
  final List<MenuItem> menuItems;

  const Merchant({
    required this.id,
    required this.shopName,
    required this.category,
    this.logoUrl,
    this.bannerUrl,
    required this.address,
    this.latitude,
    this.longitude,
    required this.rating,
    required this.ratingCount,
    required this.avgPrepMinutes,
    required this.minOrderAmount,
    required this.isOpen,
    required this.status,
    this.menuItems = const [],
  });

  factory Merchant.fromJson(Map<String, dynamic> j) => Merchant(
        id:             j['id'] as String,
        shopName:       j['shop_name'] as String,
        category:       j['category'] as String,
        logoUrl:        j['logo_url'] as String?,
        bannerUrl:      j['banner_url'] as String?,
        address:        j['address'] as String,
        latitude:       j['latitude'] != null ? parseNum(j['latitude']) : null,
        longitude:      j['longitude'] != null ? parseNum(j['longitude']) : null,
        rating:         parseNum(j['rating']),
        ratingCount:    j['rating_count'] as int? ?? 0,
        avgPrepMinutes: j['avg_prep_minutes'] as int? ?? 20,
        minOrderAmount: parseNum(j['min_order_amount']),
        isOpen:         j['is_open'] as bool? ?? true,
        status:         j['status'] as String? ?? 'active',
        menuItems: (j['menu_items'] as List<dynamic>?)
                ?.map((e) => MenuItem.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

// ── Menu Item ─────────────────────────────────────────────────────────────────
class MenuItem {
  final String id;
  final String merchantId;
  final String name;
  final String? description;
  final String category;
  final String? photoUrl;
  final double price;
  final double effectivePrice;
  final bool isAvailable;
  final int prepMinutes;

  const MenuItem({
    required this.id,
    required this.merchantId,
    required this.name,
    this.description,
    required this.category,
    this.photoUrl,
    required this.price,
    required this.effectivePrice,
    required this.isAvailable,
    required this.prepMinutes,
  });

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id:             j['id'] as String,
        merchantId:     j['merchant_id'] as String,
        name:           j['name'] as String,
        description:    j['description'] as String?,
        category:       j['category'] as String,
        photoUrl:       j['photo_url'] as String?,
        price:          parseNum(j['price']),
        effectivePrice: j['effective_price'] != null
            ? parseNum(j['effective_price'])
            : parseNum(j['price']),
        isAvailable:    j['is_available'] as bool? ?? true,
        prepMinutes:    j['prep_minutes'] as int? ?? 15,
      );
}

// ── Cart ──────────────────────────────────────────────────────────────────────
class CartItem {
  final MenuItem item;
  int quantity;

  CartItem({required this.item, this.quantity = 1});

  double get lineTotal => item.effectivePrice * quantity;
}

// ── Order ─────────────────────────────────────────────────────────────────────
class Order {
  final String id;
  final String merchantId;
  final String? courierId;
  final List<dynamic> items;
  final double subtotal;
  final double deliveryFee;
  final double surgeMultiplier;
  final double total;
  final String paymentMethod;
  final String paymentStatus;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String status;
  final String? cancellationReason;
  final String? proofType;
  final DateTime? estimatedDeliveryAt;
  final DateTime? deliveredAt;
  final int? customerRating;
  final DateTime createdAt;

  // Joined fields
  final String? merchantName;

  const Order({
    required this.id,
    required this.merchantId,
    this.courierId,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.surgeMultiplier,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    required this.status,
    this.cancellationReason,
    this.proofType,
    this.estimatedDeliveryAt,
    this.deliveredAt,
    this.customerRating,
    required this.createdAt,
    this.merchantName,
  });

  bool get isActive => ![
        'delivered',
        'cancelled',
        'delivery_failed',
      ].contains(status);

  bool get isDelivered => status == 'delivered';
  bool get isCancelled => status == 'cancelled';
  bool get canCancel => ['pending', 'confirmed'].contains(status);
  bool get canRate => isDelivered && customerRating == null;

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id:                  j['id'] as String,
        merchantId:          j['merchant_id'] as String,
        courierId:           j['courier_id'] as String?,
        items:               j['items'] as List<dynamic>? ?? [],
        subtotal:            parseNum(j['subtotal']),
        deliveryFee:         parseNum(j['delivery_fee']),
        surgeMultiplier:     parseNum(j['surge_multiplier'], 1.0),
        total:               parseNum(j['total']),
        paymentMethod:       j['payment_method'] as String,
        paymentStatus:       j['payment_status'] as String,
        deliveryAddress:     j['delivery_address'] as String,
        deliveryLatitude:    j['delivery_latitude'] != null ? parseNum(j['delivery_latitude']) : null,
        deliveryLongitude:   j['delivery_longitude'] != null ? parseNum(j['delivery_longitude']) : null,
        status:              j['status'] as String,
        cancellationReason:  j['cancellation_reason'] as String?,
        proofType:           j['proof_type'] as String?,
        estimatedDeliveryAt: j['estimated_delivery_at'] != null
            ? DateTime.tryParse(j['estimated_delivery_at'] as String)
            : null,
        deliveredAt: j['delivered_at'] != null
            ? DateTime.tryParse(j['delivered_at'] as String)
            : null,
        customerRating: j['customer_rating'] as int?,
        createdAt: DateTime.parse(j['created_at'] as String),
        merchantName: j['merchant_name'] as String?,
      );
}

// ── Order summary (GET /orders list item) ─────────────────────────────────────
class OrderSummary {
  final String id;
  final String merchantId;
  final String? merchantName;
  final String status;
  final double total;
  final int itemCount;
  final String paymentMethod;
  final String paymentStatus;
  final int? customerRating;
  final DateTime createdAt;

  const OrderSummary({
    required this.id,
    required this.merchantId,
    this.merchantName,
    required this.status,
    required this.total,
    required this.itemCount,
    required this.paymentMethod,
    required this.paymentStatus,
    this.customerRating,
    required this.createdAt,
  });

  bool get isActive => ![
        'delivered',
        'cancelled',
        'delivery_failed',
      ].contains(status);

  bool get isDelivered => status == 'delivered';
  bool get canRate => isDelivered && customerRating == null;

  factory OrderSummary.fromJson(Map<String, dynamic> j) => OrderSummary(
        id:             j['id'] as String,
        merchantId:     j['merchant_id'] as String,
        merchantName:   j['merchant_name'] as String?,
        status:         j['status'] as String,
        total:          parseNum(j['total']),
        itemCount:      (j['item_count'] as num?)?.toInt() ?? 0,
        paymentMethod:  j['payment_method'] as String,
        paymentStatus:  j['payment_status'] as String,
        customerRating: (j['customer_rating'] as num?)?.toInt(),
        createdAt:      DateTime.parse(j['created_at'] as String),
      );
}

// ── Live tracking (GET /orders/{id}/tracking) ──────────────────────────────
class OrderTracking {
  final String status;
  final bool courierAssigned;
  final String? courierName; // First name only
  final String? vehicleType;
  final double? latitude; // Only while the delivery is live
  final double? longitude;

  const OrderTracking({
    required this.status,
    required this.courierAssigned,
    this.courierName,
    this.vehicleType,
    this.latitude,
    this.longitude,
  });

  LatLng? get position => latitude != null && longitude != null
      ? LatLng(latitude!, longitude!)
      : null;

  factory OrderTracking.fromJson(Map<String, dynamic> j) => OrderTracking(
        status:          j['status'] as String,
        courierAssigned: j['courier_assigned'] as bool? ?? false,
        courierName:     j['courier_name'] as String?,
        vehicleType:     j['vehicle_type'] as String?,
        latitude:        j['latitude'] != null ? parseNum(j['latitude']) : null,
        longitude:       j['longitude'] != null ? parseNum(j['longitude']) : null,
      );
}
