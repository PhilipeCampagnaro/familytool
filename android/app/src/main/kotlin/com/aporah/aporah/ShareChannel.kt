package com.aporah.aporah

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// The system share sheet — the Android half of "aporah/share".
///
/// **Answers null, never true or false.** Android's chooser does not say whether
/// anything was sent, and a result from `startActivityForResult` only reports
/// that the chooser closed. iOS says `false` for a cancelled sheet and the Dart
/// side revokes the link it minted for it; here there is nothing to base that
/// on, so the link is kept and runs out on its own seven days later.
object ShareChannel {
    const val NAME = "aporah/share"

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "share" -> {
                val text = call.argument<String>("text")
                if (text == null) {
                    result.notImplemented()
                    return
                }
                // One string rather than two extras: most apps read EXTRA_TEXT
                // alone, and a link left in a second extra is a link dropped.
                val url = call.argument<String>("url")
                val send = Intent(Intent.ACTION_SEND).apply {
                    type = "text/plain"
                    putExtra(Intent.EXTRA_TEXT, if (url == null) text else "$text\n$url")
                }
                activity.startActivity(Intent.createChooser(send, null))
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }
}
