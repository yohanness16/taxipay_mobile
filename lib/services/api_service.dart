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
      // Null-valued keys are dropped rather than sent as JSON `null`: the
      // backend validates with Zod, whose `.optional()` accepts a *missing*
      // key but rejects an explicit null ("Expected string, received null").
      // Sending null for a blank optional field therefore failed the whole
      // signup with a 400 -- which is the common case, since the vehicle
      // number field is optional and device_id is null whenever the Android
      // ID lookup returns nothing.
      body: jsonEncode(_pruneNulls({
        'phone': phone,
        'name': name,
        'vehicle_number': vehicleNumber,
        'password': password,
        'device_id': deviceId,
      })),
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
      body: jsonEncode(_pruneNulls({'phone': phone, 'password': password, 'device_id': deviceId})),
    );
    return _decode(res);
  }

  Future<Map<String, dynamic>> checkSubscription(String phone) async {
    // Phone numbers start with "+", which must be percent-encoded to survive
    // the path segment intact -- an unencoded "+" is decoded as a space by
    // some proxies, which fails the backend's ^\+251... check with a 400.
    final res = await http.get(
      Uri.parse('$baseUrl/subscription/check/${Uri.encodeComponent(phone)}'),
    );
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
    // 403 is included because the deployed backend answers "no matching
    // payment notification yet" with 403 rather than the 404 the route
    // returns locally (an edge rewrite normalises it). Without it that
    // perfectly normal "SMS gateway hasn't caught up yet" case was thrown
    // as an ApiException instead of being returned as a retryable result.
    return _decode(res, allowedStatuses: const {200, 201, 400, 403, 404, 409, 422});
  }

  /// Strips keys whose value is null so they are omitted from the JSON body
  /// entirely. See [register] for why an explicit null is not equivalent to
  /// an absent key on this backend.
  Map<String, dynamic> _pruneNulls(Map<String, dynamic> data) =>
      Map<String, dynamic>.fromEntries(data.entries.where((e) => e.value != null));

  Map<String, dynamic> _decode(http.Response res, {Set<int>? allowedStatuses}) {
    // Guard the decode itself: a gateway/proxy error (502/504) or a crashed
    // function returns an HTML error page, and calling jsonDecode on that
    // threw a raw FormatException that bypassed every `on ApiException`
    // handler in the UI and surfaced as a generic crash.
    dynamic decoded;
    try {
      decoded = res.body.isNotEmpty ? jsonDecode(res.body) : null;
    } catch (_) {
      decoded = null;
    }
    final body = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};

    final ok = res.statusCode >= 200 && res.statusCode < 300;
    final allowed = allowedStatuses?.contains(res.statusCode) ?? false;
    if (ok || allowed) {
      return {...body, '_statusCode': res.statusCode};
    }
    throw ApiException(
      body['error']?.toString() ?? body['message']?.toString() ?? 'Request failed (${res.statusCode})',
      res.statusCode,
    );
  }
}

class ApiException implements Exception {
  ApiException(this.message, this.statusCode);
  final String message;
  final int statusCode;

  @override
  String toString() => message;
}
