// Models shared by every role. Role-specific models live in each feature.

// Safely parses a numeric value that may arrive as a JSON number or a
// Decimal-as-string (FastAPI/Pydantic serializes Decimal fields as strings).
double parseNum(dynamic v, [double fallback = 0.0]) {
  if (v == null) return fallback;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? fallback;
}

/// Roles a new account can pick. Admins are created on the server.
const kSignupRoles = ['customer', 'merchant', 'courier'];

class UserProfile {
  final String userId;
  final String? phone; // Null for Google-only accounts
  final String? email;
  final String role;
  final bool isNew;

  const UserProfile({
    required this.userId,
    this.phone,
    this.email,
    required this.role,
    this.isNew = false,
  });

  factory UserProfile.fromJson(Map<String, dynamic> j) => UserProfile(
        userId: j['user_id'] as String,
        phone: j['phone'] as String?,
        email: j['email'] as String?,
        role: j['role'] as String,
        isNew: j['is_new'] as bool? ?? false,
      );
}

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
        accessToken: j['access_token'] as String,
        refreshToken: j['refresh_token'] as String,
        user: UserProfile.fromJson(j['user'] as Map<String, dynamic>),
      );
}
