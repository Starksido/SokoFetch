library sokofetch_auth;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthService {
  final FlutterSecureStorage _storage = const FlutterSecureStorage();
  final String _tokenKey = 'sokofetch_token';

  Future<void> saveToken(String token) async {
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _tokenKey);
  }

  Future<bool> isLoggedIn() async {
    final token = await getToken();
    if (token == null) return false;
    return await validateToken(token);
  }

  Future<bool> validateToken(String token) async {
    // TODO: wire this up to your FastAPI /me endpoint
    throw UnimplementedError('Wire this up to your FastAPI /me endpoint');
  }

  Future<void> logout() async {
    await _storage.delete(key: _tokenKey);
  }
}