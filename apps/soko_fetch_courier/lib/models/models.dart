// ── Auth ──────────────────────────────────────────────────────────────────────
double parseNum(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

class UserProfile {
  final String userId;
  final String phone;
  final String role;
  const UserProfile({required this.userId, required this.phone, required this.role});
  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
    userId: j['user_id'] as String, phone: j['phone'] as String, role: j['role'] as String);
}

class AuthTokens {
  final String accessToken, refreshToken;
  final UserProfile user;
  const AuthTokens({required this.accessToken, required this.refreshToken, required this.user});
  factory AuthTokens.fromJson(Map<String, dynamic> j) => AuthTokens(
    accessToken:  j['access_token']  as String,
    refreshToken: j['refresh_token'] as String,
    user: UserProfile.fromJson(j['user'] as Map<String, dynamic>),
  );
}

// ── Courier profile ───────────────────────────────────────────────────────────
class CourierProfile {
  final String id, userId, status, vehicleType;
  final String? fullName, vehiclePlate, payoutPhone;
  final bool isOnline;
  final double rating, totalEarned, pendingPayout;
  final int ratingCount, totalDeliveries;
  final List<CourierDocument> documents;
  final DateTime? documentsVerifiedAt;

  const CourierProfile({
    required this.id, required this.userId, required this.status,
    required this.vehicleType, this.fullName, this.vehiclePlate, this.payoutPhone,
    required this.isOnline, required this.rating, required this.totalEarned,
    required this.pendingPayout, required this.ratingCount,
    required this.totalDeliveries, required this.documents, this.documentsVerifiedAt,
  });

  bool get isActive         => status == 'active';
  bool get isApproved       => status == 'approved' || status == 'active';
  bool get needsDocs        => status == 'registered';
  bool get isPendingReview  => status == 'under_review' || status == 'documents_submitted';
  bool get isRejected       => status == 'rejected';
  bool get canGoOnline      => isActive;

  factory CourierProfile.fromJson(Map<String, dynamic> j) => CourierProfile(
    id:               j['id'] as String,
    userId:           j['user_id'] as String,
    status:           j['status'] as String,
    vehicleType:      j['vehicle_type'] as String? ?? 'motorcycle',
    fullName:         j['full_name'] as String?,
    vehiclePlate:     j['vehicle_plate'] as String?,
    payoutPhone:      j['payout_phone'] as String?,
    isOnline:         j['is_online'] as bool? ?? false,
    rating:           parseNum(j['rating'], 5.0),
    totalEarned:      parseNum(j['total_earned']),
    pendingPayout:    parseNum(j['pending_payout']),
    ratingCount:      j['rating_count'] as int? ?? 0,
    totalDeliveries:  j['total_deliveries'] as int? ?? 0,
    documents: (j['documents'] as List<dynamic>?)
        ?.map((e) => CourierDocument.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    documentsVerifiedAt: j['documents_verified_at'] != null
        ? DateTime.tryParse(j['documents_verified_at'] as String) : null,
  );
}

class CourierDocument {
  final String id, docType;
  final bool isVerified;
  final DateTime uploadedAt;
  final DateTime? verifiedAt;
  const CourierDocument({
    required this.id, required this.docType, required this.isVerified,
    required this.uploadedAt, this.verifiedAt,
  });
  factory CourierDocument.fromJson(Map<String, dynamic> j) => CourierDocument(
    id:          j['id'] as String,
    docType:     j['doc_type'] as String,
    isVerified:  j['is_verified'] as bool? ?? false,
    uploadedAt:  DateTime.parse(j['uploaded_at'] as String),
    verifiedAt:  j['verified_at'] != null ? DateTime.tryParse(j['verified_at'] as String) : null,
  );
}

// ── Order ─────────────────────────────────────────────────────────────────────
class Order {
  final String id, merchantId, customerId, status, paymentMethod, deliveryAddress;
  final String? courierId, deliveryNotes, specialInstructions;
  final List<dynamic> items;
  final int itemCount;
  final double total, courierPayout, subtotal;
  final double? deliveryLatitude, deliveryLongitude;
  final DateTime createdAt;
  final DateTime? estimatedDeliveryAt, pickedUpAt, deliveredAt;

  // Merchant info (joined)
  final String? merchantName, merchantAddress;
  final double? merchantLat, merchantLon;

  const Order({
    required this.id, required this.merchantId, required this.customerId,
    required this.status, required this.paymentMethod, required this.deliveryAddress,
    this.courierId, this.deliveryNotes, this.specialInstructions,
    required this.items, required this.itemCount,
    required this.total, required this.courierPayout, required this.subtotal,
    this.deliveryLatitude, this.deliveryLongitude,
    required this.createdAt, this.estimatedDeliveryAt,
    this.pickedUpAt, this.deliveredAt,
    this.merchantName, this.merchantAddress, this.merchantLat, this.merchantLon,
  });

  bool get isReadyForPickup => status == 'ready_for_pickup';
  bool get isPickedUp       => status == 'picked_up';
  bool get isInTransit      => status == 'in_transit';
  bool get isDelivered      => status == 'delivered';
  bool get isActive         => ['ready_for_pickup','picked_up','in_transit'].contains(status);

  factory Order.fromJson(Map<String, dynamic> j) => Order(
    id:                  j['id'] as String,
    merchantId:          j['merchant_id'] as String,
    customerId:          j['customer_id'] as String,
    status:              j['status'] as String,
    paymentMethod:       j['payment_method'] as String,
    deliveryAddress:     j['delivery_address'] as String,
    courierId:           j['courier_id'] as String?,
    deliveryNotes:       j['delivery_notes'] as String?,
    specialInstructions: j['special_instructions'] as String?,
    items:               j['items'] as List<dynamic>? ?? [],
    itemCount:           j['item_count'] as int? ?? 0,
    total:               parseNum(j['total']),
    courierPayout:       parseNum(j['courier_payout']),
    subtotal:            parseNum(j['subtotal']),
    deliveryLatitude:    j['delivery_latitude'] != null ? parseNum(j['delivery_latitude']) : null,
    deliveryLongitude:   j['delivery_longitude'] != null ? parseNum(j['delivery_longitude']) : null,
    createdAt:           DateTime.parse(j['created_at'] as String),
    estimatedDeliveryAt: j['estimated_delivery_at'] != null
        ? DateTime.tryParse(j['estimated_delivery_at'] as String) : null,
    pickedUpAt:  j['picked_up_at']  != null ? DateTime.tryParse(j['picked_up_at']  as String) : null,
    deliveredAt: j['delivered_at']  != null ? DateTime.tryParse(j['delivered_at']  as String) : null,
    merchantName:    j['merchant_name']    as String?,
    merchantAddress: j['merchant_address'] as String?,
    merchantLat:     j['merchant_lat'] != null ? parseNum(j['merchant_lat']) : null,
    merchantLon:     j['merchant_lon'] != null ? parseNum(j['merchant_lon']) : null,
  );
}

// ── Earnings ──────────────────────────────────────────────────────────────────
class EarningsDay {
  final String date;
  final int deliveries;
  final double earned;
  const EarningsDay({required this.date, required this.deliveries, required this.earned});
  factory EarningsDay.fromJson(Map<String, dynamic> j) => EarningsDay(
    date:        j['date'] as String,
    deliveries:  j['deliveries'] as int? ?? 0,
    earned:      parseNum(j['earned']),
  );
}

// Required document types
const kRequiredDocs = [
  'national_id_front',
  'national_id_back',
  'driving_license',
  'vehicle_photo',
  'selfie_with_id',
];

const kDocLabels = {
  'national_id_front': 'National ID — Front',
  'national_id_back':  'National ID — Back',
  'driving_license':   'Driving License',
  'vehicle_photo':     'Vehicle / Motorcycle Photo',
  'selfie_with_id':    'Selfie Holding Your ID',
};
