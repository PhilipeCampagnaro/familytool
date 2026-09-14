package com.aporah.aporah

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    /// The one method channel Android implements by hand.
    ///
    /// Everything else `lib/services/` needs off iOS comes from a plugin —
    /// `url_launcher`, `image_picker`, `file_picker` — because a plugin is the
    /// whole of the work there. Spend capture has no plugin to reach for: it is
    /// a notification listener the system starts on its own, a credential in the
    /// keystore and a POST, none of which any package does for us.
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SpendChannel.NAME)
            .setMethodCallHandler { call, result ->
                SpendChannel.handle(applicationContext, call, result)
            }
    }
}
