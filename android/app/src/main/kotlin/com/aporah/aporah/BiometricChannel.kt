package com.aporah.aporah

import android.app.Activity
import android.app.KeyguardManager
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.biometrics.BiometricManager
import android.hardware.biometrics.BiometricPrompt
import android.os.Build
import android.os.CancellationSignal
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/// The app lock — the Android half of "aporah/biometrics".
///
/// The framework's own `android.hardware.biometrics.BiometricPrompt`, not
/// androidx.biometric: the androidx one needs a `FragmentActivity`, which would
/// mean swapping `MainActivity`'s base class for one feature. The price is that
/// the lock starts at **API 29** (Android 10), the first release where the
/// framework prompt falls back to the screen lock. Below that `kind` answers
/// `none` and the Settings row is absent — a fingerprint-only lock with no way
/// past a locked-out sensor is worse than no lock.
///
/// Android does not say which sensor the prompt will use when a phone has two,
/// so `kind` names one only when there is exactly one to name.
object BiometricChannel {
    const val NAME = "aporah/biometrics"

    fun handle(activity: Activity, call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "kind" -> result.success(kind(activity))
            "authenticate" -> authenticate(activity, call.argument<String>("reason") ?: " ", result)
            else -> result.notImplemented()
        }
    }

    private fun kind(context: Context): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return "none"
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        if (keyguard?.isDeviceSecure != true) return "none"
        val manager = context.getSystemService(BiometricManager::class.java)
        val enrolled = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            manager?.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_WEAK)
        } else {
            @Suppress("DEPRECATION")
            manager?.canAuthenticate()
        } == BiometricManager.BIOMETRIC_SUCCESS
        if (!enrolled) return "passcode"
        val pm = context.packageManager
        val face = pm.hasSystemFeature(PackageManager.FEATURE_FACE)
        val finger = pm.hasSystemFeature(PackageManager.FEATURE_FINGERPRINT)
        return when {
            finger && !face -> "fingerprint"
            face && !finger -> "face"
            else -> "biometrics"
        }
    }

    private fun authenticate(activity: Activity, reason: String, result: MethodChannel.Result) {
        if (kind(activity) == "none") {
            result.success("unavailable")
            return
        }
        val builder = BiometricPrompt.Builder(activity).setTitle(reason)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            builder.setAllowedAuthenticators(
                BiometricManager.Authenticators.BIOMETRIC_WEAK or
                    BiometricManager.Authenticators.DEVICE_CREDENTIAL,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setDeviceCredentialAllowed(true)
        }
        // One answer per request: `onAuthenticationFailed` is a single
        // unrecognised finger and the prompt stays up, so it answers nothing.
        var answered = false
        fun answer(value: String) {
            if (answered) return
            answered = true
            result.success(value)
        }
        builder.build().authenticate(
            CancellationSignal(),
            activity.mainExecutor,
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(r: BiometricPrompt.AuthenticationResult?) = answer("ok")
                override fun onAuthenticationError(code: Int, message: CharSequence?) = answer("failed")
            },
        )
    }
}
