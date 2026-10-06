import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Answers Dio requests in tests instead of the network.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions o) handler;
  final List<RequestOptions> requests = [];

  int count(String path) => requests.where((r) => r.path == path).length;

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? requestStream,
      Future<void>? cancelFuture) {
    requests.add(o);
    return handler(o);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(int status, Object? body) => ResponseBody.fromString(
      jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

Map<String, dynamic> tokenJson(
        {String access = 'access',
        String refresh = 'refresh',
        String role = 'customer',
        bool isNew = false}) =>
    {
      'access_token': access,
      'refresh_token': refresh,
      'token_type': 'bearer',
      'expires_in': 1800,
      'user': {
        'user_id': 'u1',
        'phone': '+254700000000',
        'email': null,
        'role': role,
        'is_new': isNew,
      },
    };

/// Secure-storage keys used by TokenStore.
Map<String, String> storedSession({required String role}) => {
      'sf_access_token': 'access',
      'sf_refresh_token': 'refresh',
      'sf_user_id': 'u1',
      'sf_user_role': role,
    };
