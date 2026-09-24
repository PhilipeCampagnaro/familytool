package com.aporah.aporah

import android.content.Context
import android.os.Build
import android.provider.Settings
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/// The Android end of "aporah/spend", answering the same calls
/// `ios/Runner/SpendCapture.swift` answers, plus the two this platform needs.
///
/// Dart owns enrolment on both platforms and neither platform's capture code
/// asks Dart for anything at the moment a payment arrives — see
/// [SpendNotificationListener]. So what crosses here is only plumbing: the token
/// from `spend-enroll`, and the device's name and id so the enrolment can be
/// listed in Settings and revoked.
object SpendChannel {
    const val NAME = "aporah/spend"

    fun handle(context: Context, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "hasToken" -> result.success(SpendCredential.hasToken(context))

            "tokenOwner" -> result.success(SpendCredential.tokenOwner(context))

            "storeToken" -> {
                val token = call.argument<String>("token")
                val endpoint = call.argument<String>("endpoint")
                val apiKey = call.argument<String>("api_key")
                if (token.isNullOrEmpty() || endpoint.isNullOrEmpty() || apiKey.isNullOrEmpty()) {
                    result.error("bad_args", "token, endpoint and api_key required", null)
                } else {
                    SpendCredential.save(context, token, endpoint, apiKey, call.argument<String>("owner") ?: "")
                    result.success(null)
                }
            }

            "clearToken" -> {
                SpendCredential.clear(context)
                result.success(null)
            }

            "describeDevice" -> result.success(
                mapOf(
                    "label" to deviceLabel(context),
                    "uid" to SpendCredential.deviceUid(context),
                    // The iOS side answers this for iOS 16 and App Intents. Here
                    // it asks whether the OS can capture at all, and every
                    // Android this app installs on can: a notification listener
                    // has existed since API 18 and the floor is 24.
                    "can_run_intents" to true,
                    "has_notification_access" to SpendNotificationListener.hasAccess(context),
                )
            )

            "hasNotificationAccess" ->
                result.success(SpendNotificationListener.hasAccess(context))

            "openNotificationAccess" -> {
                context.startActivity(SpendNotificationListener.accessSettingsIntent())
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /// What to call this phone in the household's device list.
    ///
    /// The name the user gave it if there is one — the closest thing Android has
    /// to `UIDevice.current.name`, and the only version of this that reads as
    /// *their* phone rather than a model number. It is a global setting rather
    /// than a permissioned one, and it is read once, at enrolment.
    private fun deviceLabel(context: Context): String {
        val chosen = try {
            Settings.Global.getString(context.contentResolver, "device_name")
        } catch (e: Exception) {
            null
        }
        if (!chosen.isNullOrBlank()) return chosen.trim()

        val maker = Build.MANUFACTURER.orEmpty().trim()
        val model = Build.MODEL.orEmpty().trim()
        val name = when {
            model.startsWith(maker, ignoreCase = true) -> model
            maker.isEmpty() -> model
            else -> "$maker $model"
        }
        return if (name.isBlank()) {
            "Android"
        } else {
            name.replaceFirstChar { if (it.isLowerCase()) it.titlecase(Locale.getDefault()) else it.toString() }
        }
    }
}
