package com.example.telebirr_driver_assistant

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // Exposes Settings.Secure.ANDROID_ID to Dart. This value is stable per
    // (app signing key, device, user profile) and survives SIM swaps/app
    // reinstalls, which is exactly what makes it useful as a free-trial
    // abuse signal -- it does NOT change when someone pops in a new SIM
    // to register a fresh account, unlike the phone number itself. It
    // resets on a full factory reset, so treat it as a deterrent, not an
    // unbeatable lock. Reading it needs no special permission.
    private val channel = "com.example.telebirr_driver_assistant/device"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            if (call.method == "getAndroidId") {
                val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                result.success(id)
            } else {
                result.notImplemented()
            }
        }
    }
}
