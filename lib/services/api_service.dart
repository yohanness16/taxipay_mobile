import 'dart:convert';
import 'package:http/http.dart' as http;

/// Thin wrapper around the Hono.js backend hosted on Vercel.
/// Set [baseUrl] to your deployed Vercel URL, e.g.
/// https://telebirr-driver-backend.vercel.app/api
class ApiService {
  ApiService({required this.baseUrl});

  final String baseUrl;

  Future<Map<String, dynamic>> register({
    required String phone,
    required String name,
    String? vehicleNumber,
    required String password,
    String? deviceId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone': phone,
        'name': name,
        'vehicle_number': vehicleNumber,
        'password': password,
        'device_id': deviceId,
      }),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> login({
    required String phone,
    required String password,
    String? deviceId,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'password': password, 'device_id': deviceId}),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> checkSubscription(String phone) async {
    final res = await http.get(Uri.parse('$baseUrl/subscription/check/$phone'));
    return _decode(res);
  }

  /// Submits the Telebirr SMS text the driver received confirming their own
  /// subscription payment. The backend re-extracts the transaction number
  /// itself and cross-checks it against the payment notifications it
  /// received independently via its own SMS gateway webhook -- so [smsText]
  /// should be passed through close to verbatim rather than pre-parsed.
  Future<Map<String, dynamic>> verifyTelebirrPayment({
    required int driverId,
    required double amount,
    required String smsText,
  }) async {
    final res = await http.post(
      Uri.parse('$baseUrl/subscription/verify-telebirr'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'driverId': driverId,
        'amount': amount,
        'smsText': smsText,
      }),
    );
    return _decode(res, allowedStatuses: const {200, 201, 400, 404, 409, 422});
  }

  Map<String, dynamic> _decode(http.Response res, {Set<int>? allowedStatuses}) {
    final body = res.body.isNotEmpty ? jsonDecode(res.body) as Map<String, dynamic> : <String, dynamic>{};
    final ok = res.statusCode >= 200 && res.statusCode < 300;
    final allowed = allowedStatuses?.contains(res.statusCode) ?? false;
    if (ok || allowed) {
      return {...body, '_statusCode': res.statusCode};
    }
    throw ApiException(body['error']?.toString() ?? body['message']?.toString() ?? 'Request failed (${res.statusCode})', res.statusCode);
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
