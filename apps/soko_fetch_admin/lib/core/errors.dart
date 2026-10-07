import 'package:dio/dio.dart';

Map? _detail(Object e) {
  if (e is! DioException) return null;
  final data = e.response?.data;
  final detail = data is Map ? data['detail'] : null;
  return detail is Map ? detail : null;
}

/// The `code` of a backend error: {"detail": {"code": ..., "message": ...}}.
String? errorCode(Object e) => _detail(e)?['code'] as String?;

/// A user-facing message for a failed request.
String errorMessage(Object e,
    [String fallback = 'Something went wrong. Please try again.']) {
  if (e is! DioException) return fallback;
  final message = _detail(e)?['message'];
  if (message is String) return message;
  final data = e.response?.data;
  if (data is Map && data['detail'] is List) {
    return 'Please check the details and try again.';
  }
  if (e.response == null) return 'Could not reach the server.';
  return fallback;
}
