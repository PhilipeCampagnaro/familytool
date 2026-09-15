package com.aporah.aporah

import android.app.Activity
import com.google.android.play.core.review.ReviewManagerFactory
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// Google Play's in-app review flow — the Android half of "aporah/review".
///
/// Like Apple's, it says nothing about whether a review was left:
/// `launchReviewFlow` completes the same way for five stars and for a swipe away,
/// and Play applies its own quota silently. It also **only works in a build
/// installed from Play** (internal testing counts); on a sideloaded debug build
/// it completes and shows nothing, which is not a bug in this file.
object AppReviewChannel {
    const val NAME = "aporah/review"

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestReview" -> {
                val manager = ReviewManagerFactory.create(activity)
                manager.requestReviewFlow().addOnCompleteListener { request ->
                    if (!request.isSuccessful) {
                        result.success(false)
                        return@addOnCompleteListener
                    }
                    manager.launchReviewFlow(activity, request.result)
                        .addOnCompleteListener { result.success(true) }
                }
            }
            "version" -> {
                @Suppress("DEPRECATION")
                val info = activity.packageManager.getPackageInfo(activity.packageName, 0)
                result.success(info.versionName)
            }
            else -> result.notImplemented()
        }
    }
}
