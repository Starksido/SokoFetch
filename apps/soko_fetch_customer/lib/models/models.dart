// lib/models/models.dart
// All data models for the customer app.


// Safely parses a numeric value that may arrive as a JSON number or a
// Decimal-as-string (FastAPI/Pydantic serializes Decimal fields as strings).
double parseNum(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}
// ── User ──────────────────────────────────────────────────────────────────────
class UserProfile {
  final String userId;
  final String? phone;
  final String? email;
  final String role;
  final bool isNew;

  const UserProfile({
    required this.userId,
    this.phone,
    this.email,
    required this.role,
    required this.isNew,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: j['user_id'] as String,
        phone:  j['phone'] as String?,
        email:  j['email'] as String?,
        role:   j['role']    as String,
        isNew:  j['is_new']  as bool? ?? false,
      );
}
// ── Auth tokens ───────────────────────────────────────────────────────────────
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final UserProfile user;

  const AuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.user,
  });

  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken:  j['access_token']  as String,
        refreshToken: j['refresh_token'] as String,
        user: UserProfile.fromJson(j['user'] as Map<String, dynamic>),
      );
}

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

// ── Courier location ──────────────────────────────────────────────────────────
class CourierLocation {
  final double latitude;
  final double longitude;
  final int? etaMinutes;
  final DateTime updatedAt;

  const CourierLocation({
    required this.latitude,
    required this.longitude,
    this.etaMinutes,
    required this.updatedAt,
  });

  factory CourierLocation.fromJson(Map<String, dynamic> j) => CourierLocation(
        latitude:   parseNum(j['latitude']),
        longitude:  parseNum(j['longitude']),
        etaMinutes: j['eta_minutes'] as int?,
        updatedAt:  DateTime.tryParse(j['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
}

