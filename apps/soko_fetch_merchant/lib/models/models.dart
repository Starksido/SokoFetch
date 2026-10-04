// Safely parses a numeric value that may arrive as a JSON number or a
// Decimal-as-string (FastAPI/Pydantic serializes Decimal fields as strings).
double parseNum(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

// ── Auth ──────────────────────────────────────────────────────────────────────
class UserProfile {
  final String userId;
  final String phone;
  final String role;
  const UserProfile(
      {required this.userId, required this.phone, required this.role});
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: j['user_id'] as String,
        phone:  j['phone']   as String,
        role:   j['role']    as String,
      );
}

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final UserProfile user;
  const AuthTokens(
      {required this.accessToken,
      required this.refreshToken,
      required this.user});
  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
        accessToken:  j['access_token']  as String,
        refreshToken: j['refresh_token'] as String,
        user: UserProfile.fromJson(j['user'] as Map<String, dynamic>),
      );
}

// ── Merchant profile ──────────────────────────────────────────────────────────
class MerchantProfile {
  final String id;
  final String shopName;
  final String category;
  final String address;
  final String status;
  final bool isOpen;
  final double rating;
  final int ratingCount;
  final int avgPrepMinutes;
  final double commissionRate;
  final String? logoUrl;
  final String? payoutPhone;

  const MerchantProfile({
    required this.id,
    required this.shopName,
    required this.category,
    required this.address,
    required this.status,
    required this.isOpen,
    required this.rating,
    required this.ratingCount,
    required this.avgPrepMinutes,
    required this.commissionRate,
    this.logoUrl,
    this.payoutPhone,
  });

  bool get isActive => status == 'active';
  bool get isPending => status == 'pending_review';

  factory MerchantProfile.fromJson(Map<String, dynamic> j) => MerchantProfile(
        id:             j['id'] as String,
        shopName:       j['shop_name'] as String,
        category:       j['category'] as String,
        address:        j['address'] as String,
        status:         j['status'] as String,
        isOpen:         j['is_open'] as bool? ?? true,
        rating:         parseNum(j['rating']),
        ratingCount:    j['rating_count'] as int? ?? 0,
        avgPrepMinutes: j['avg_prep_minutes'] as int? ?? 20,
        commissionRate: parseNum(j['commission_rate'], 20.0),
        logoUrl:        j['logo_url'] as String?,
        payoutPhone:    j['payout_phone'] as String?,
      );
}

// ── Menu item ─────────────────────────────────────────────────────────────────
class MenuItem {
  final String id;
  final String name;
  final String? description;
  final String category;
  final String? photoUrl;
  final double price;
  final double discountPct;
  final double effectivePrice;
  final bool isAvailable;
  final int prepMinutes;
  final int sortOrder;

  const MenuItem({
    required this.id,
    required this.name,
    this.description,
    required this.category,
    this.photoUrl,
    required this.price,
    required this.discountPct,
    required this.effectivePrice,
    required this.isAvailable,
    required this.prepMinutes,
    required this.sortOrder,
  });

  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        id:            j['id'] as String,
        name:          j['name'] as String,
        description:   j['description'] as String?,
        category:      j['category'] as String,
        photoUrl:      j['photo_url'] as String?,
        price:         double.parse(j['price'].toString()),
        discountPct:   double.tryParse(j['discount_pct']?.toString() ?? '') ?? 0,
        effectivePrice: j['effective_price'] != null
            ? parseNum(j['effective_price'])
            : double.parse(j['price'].toString()),
        isAvailable:   j['is_available'] as bool? ?? true,
        prepMinutes:   j['prep_minutes'] as int? ?? 15,
        sortOrder:     j['sort_order'] as int? ?? 0,
      );
}

// ── Order ─────────────────────────────────────────────────────────────────────
class Order {
  final String id;
  final String customerId;
  final String merchantId;
  final String? courierId;
  final List<dynamic> items;
  final int itemCount;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final double merchantCommission;
  final String paymentMethod;
  final String paymentStatus;
  final String deliveryAddress;
  final String? deliveryNotes;
  final String? specialInstructions;
  final String status;
  final String? cancellationReason;
  final DateTime? estimatedPickupAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime createdAt;

  const Order({
    required this.id,
    required this.customerId,
    required this.merchantId,
    this.courierId,
    required this.items,
    required this.itemCount,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.merchantCommission,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.deliveryAddress,
    this.deliveryNotes,
    this.specialInstructions,
    required this.status,
    this.cancellationReason,
    this.estimatedPickupAt,
    this.pickedUpAt,
    this.deliveredAt,
    required this.createdAt,
  });

  bool get isPending        => status == 'pending';
  bool get isPaid           => paymentStatus == 'paid';
  /// Only paid orders can be accepted (the backend rejects confirming unpaid ones).
  bool get awaitingPayment  => isPending && !isPaid;
  bool get isConfirmed      => status == 'confirmed';
  bool get isPreparing      => status == 'preparing';
  bool get isReadyForPickup => status == 'ready_for_pickup';
  bool get isTerminal =>
      ['delivered', 'cancelled', 'delivery_failed'].contains(status);

  double get netPayout => subtotal - merchantCommission;

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id:                 j['id'] as String,
        customerId:         j['customer_id'] as String,
        merchantId:         j['merchant_id'] as String,
        courierId:          j['courier_id'] as String?,
        items:              j['items'] as List<dynamic>? ?? [],
        itemCount:          j['item_count'] as int? ?? 0,
        subtotal:           parseNum(j['subtotal']),
        deliveryFee:        parseNum(j['delivery_fee']),
        total:              parseNum(j['total']),
        merchantCommission: parseNum(j['merchant_commission']),
        paymentMethod:      j['payment_method'] as String,
        paymentStatus:      j['payment_status'] as String,
        deliveryAddress:    j['delivery_address'] as String,
        deliveryNotes:      j['delivery_notes'] as String?,
        specialInstructions: j['special_instructions'] as String?,
        status:             j['status'] as String,
        cancellationReason: j['cancellation_reason'] as String?,
        estimatedPickupAt: j['estimated_pickup_at'] != null
            ? DateTime.tryParse(j['estimated_pickup_at'] as String)
            : null,
        pickedUpAt: j['picked_up_at'] != null
            ? DateTime.tryParse(j['picked_up_at'] as String)
            : null,
        deliveredAt: j['delivered_at'] != null
            ? DateTime.tryParse(j['delivered_at'] as String)
            : null,
        createdAt: DateTime.parse(j['created_at'] as String),
      );
}

// ── Earnings ──────────────────────────────────────────────────────────────────
class DailyEarnings {
  final String date;
  final int totalOrders;
  final double grossRevenue;
  final double commissionDeducted;
  final double netPayout;

  const DailyEarnings({
    required this.date,
    required this.totalOrders,
    required this.grossRevenue,
    required this.commissionDeducted,
    required this.netPayout,
  });

  factory DailyEarnings.fromJson(Map<String, dynamic> j) => DailyEarnings(
        date:               j['date'] as String,
        totalOrders:        j['total_orders'] as int,
        grossRevenue:       parseNum(j['gross_revenue']),
        commissionDeducted: parseNum(j['commission_deducted']),
        netPayout:          parseNum(j['net_payout']),
      );
}






