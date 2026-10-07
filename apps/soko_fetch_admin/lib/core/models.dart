// Rider models as the admin endpoints return them.

double parseNum(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

class CourierProfile {
  final String id, userId, status, vehicleType;
  final String? fullName, vehiclePlate;
  final List<CourierDocument> documents;

  const CourierProfile({
    required this.id,
    required this.userId,
    required this.status,
    required this.vehicleType,
    this.fullName,
    this.vehiclePlate,
    required this.documents,
  });

  factory CourierProfile.fromJson(Map<String, dynamic> j) => CourierProfile(
        id: j['id'] as String,
        userId: j['user_id'] as String,
        status: j['status'] as String,
        vehicleType: j['vehicle_type'] as String? ?? 'motorcycle',
        fullName: j['full_name'] as String?,
        vehiclePlate: j['vehicle_plate'] as String?,
        documents: (j['documents'] as List<dynamic>?)
                ?.map((e) => CourierDocument.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [],
      );
}

class CourierDocument {
  final String id, docType;
  final bool isVerified;
  final DateTime uploadedAt;

  const CourierDocument({
    required this.id,
    required this.docType,
    required this.isVerified,
    required this.uploadedAt,
  });

  factory CourierDocument.fromJson(Map<String, dynamic> j) => CourierDocument(
        id: j['id'] as String,
        docType: j['doc_type'] as String,
        isVerified: j['is_verified'] as bool? ?? false,
        uploadedAt: DateTime.parse(j['uploaded_at'] as String),
      );
}

// Must match REQUIRED_DOCUMENTS on the backend
const kRequiredDocs = [
  'national_id_front',
  'national_id_back',
  'driving_license',
  'vehicle_photo',
  'selfie_with_id',
];

const kDocLabels = {
  'national_id_front': 'National ID — Front',
  'national_id_back': 'National ID — Back',
  'driving_license': 'Driving License',
  'vehicle_photo': 'Vehicle / Motorcycle Photo',
  'selfie_with_id': 'Selfie Holding Your ID',
};
