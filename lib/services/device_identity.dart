import 'package:flutter/services.dart';

/// Reads a stable per-device identifier (Android ID) to send to the backend
/// at registration, so it can tell "same phone number, brand new SIM" apart
/// from "genuinely new device" when deciding whether a free trial applies.
///
/// This is a deterrent against free-trial abuse, not a hard guarantee: the
/// value survives SIM swaps and app reinstalls (which is the whole point),
/// but resets on a full factory reset. It needs no special Android
/// permission to read.
class DeviceIdentity {
  static const _channel = MethodChannel('com.example.telebirr_driver_assistant/device');

  String? _cached;

  Future<String?> getId() async {
    if (_cached != null) return _cached;
    try {
      final id = await _channel.invokeMethod<String>('getAndroidId');
      _cached = (id == null || id.isEmpty) ? null : id;
      return _cached;
    } catch (_) {
      // Never let a device-id read failure block registration/login --
      // this is a fraud signal, not a required field.
      return null;
    }
  }
}
