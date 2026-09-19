package com.aporah.aporah

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// The method channels Android implements by hand.
    ///
    /// Everything else `lib/services/` needs off iOS comes from a plugin —
    /// `url_launcher`, `image_picker`, `file_picker` — because a plugin is the
    /// whole of the work there. Spend capture has no plugin to reach for: it is
    /// a notification listener the system starts on its own, a credential in the
    /// keystore and a POST, none of which any package does for us.
    ///
    /// Notifications and the review prompt are by hand for a different reason:
    /// the plugins for them carry an iOS half, and the iOS build runs on Swift
    /// Package Manager with no Podfile. See LocalNotifications.kt.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        MethodChannel(messenger, SpendChannel.NAME)
            .setMethodCallHandler { call, result ->
                SpendChannel.handle(applicationContext, call, result)
            }
        MethodChannel(messenger, LocalNotifications.NAME)
            .setMethodCallHandler { call, result ->
                LocalNotifications.handle(this, call, result)
            }
        MethodChannel(messenger, AppReviewChannel.NAME)
            .setMethodCallHandler { call, result ->
                AppReviewChannel.handle(this, call, result)
            }
        MethodChannel(messenger, ShareChannel.NAME)
            .setMethodCallHandler { call, result ->
                ShareChannel.handle(this, call, result)
            }
        MethodChannel(messenger, BiometricChannel.NAME)
            .setMethodCallHandler { call, result ->
                BiometricChannel.handle(this, call, result)
            }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == LocalNotifications.PERMISSION_REQUEST) {
            LocalNotifications.onPermissionResult(this)
        }
    }
}
