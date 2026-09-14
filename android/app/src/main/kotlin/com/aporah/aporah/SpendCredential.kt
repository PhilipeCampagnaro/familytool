package com.aporah.aporah

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import java.security.KeyStore
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/// Where this phone keeps its permission to file wallet transactions.
///
/// The Android twin of `ios/Runner/SpendCapture.swift`, and it exists for the
/// same reason: the thing that receives a payment — there a locked-phone App
/// Intent, here [SpendNotificationListener] — runs with no Flutter engine and no
/// Supabase session, so it cannot ask Dart for anything. Everything it needs is
/// put here once at enrolment by `lib/services/spend_intent.dart`.
///
/// **Not `EncryptedSharedPreferences`.** All of `androidx.security:security-crypto`
/// was deprecated in April 2025 with no replacement release, and its two known
/// failure modes — a strict-mode violation on the main thread and an
/// unrecoverable keyset corruption — are both worse here than anywhere else: a
/// corrupted keyset would silently stop a household's payments arriving with
/// nothing on screen to say so. This is the same construction without the
/// library: one AES-GCM key that never leaves the AndroidKeyStore, wrapping
/// values in an ordinary app-private preferences file.
///
/// **The storage class is the load-bearing part, exactly as
/// `kSecAttrAccessibleAfterFirstUnlock` is on iOS.** App-private files are
/// credential-encrypted, so they become readable once the user has unlocked the
/// phone at least once since boot — which for a phone somebody is paying with is
/// always true. Device-encrypted storage would be readable before that first
/// unlock and is not worth the weaker boundary for a case that cannot arise.
///
/// The key is not `setUserAuthenticationRequired`, and must not be: the listener
/// reads it seconds after a tap, with the phone back in a pocket.
object SpendCredential {
    private const val PREFS = "aporah.spend"
    private const val KEY_ALIAS = "aporah.spend.credential"

    private const val TOKEN = "ingest-token"
    private const val ENDPOINT = "ingest-endpoint"
    private const val API_KEY = "ingest-api-key"

    /// Survives [clear] on purpose. It is not a credential — it is the name the
    /// server files this device under, and losing it on a revoke would make the
    /// next enrolment add a second row instead of rotating the first.
    private const val DEVICE_UID = "device-uid"

    private const val GCM_TAG_BITS = 128
    private const val GCM_IV_BYTES = 12

    /// All three or nothing, like the iOS side. A token with no endpoint is not
    /// a usable credential, and posting to a stale address would fail in the
    /// background where nobody would ever see it.
    data class Stored(val token: String, val endpoint: String, val apiKey: String)

    fun save(context: Context, token: String, endpoint: String, apiKey: String) {
        prefs(context).edit()
            .putString(TOKEN, encrypt(token))
            .putString(ENDPOINT, encrypt(endpoint))
            .putString(API_KEY, encrypt(apiKey))
            .apply()
    }

    fun clear(context: Context) {
        prefs(context).edit().remove(TOKEN).remove(ENDPOINT).remove(API_KEY).apply()
    }

    fun hasToken(context: Context): Boolean = !read(context, TOKEN).isNullOrEmpty()

    fun load(context: Context): Stored? {
        val token = read(context, TOKEN)
        val endpoint = read(context, ENDPOINT)
        val apiKey = read(context, API_KEY)
        if (token.isNullOrEmpty() || endpoint.isNullOrEmpty() || apiKey.isNullOrEmpty()) return null
        return Stored(token, endpoint, apiKey)
    }

    /// This install's own id, minted once. The analogue of `identifierForVendor`:
    /// it resets when the app's data is cleared, never leaves our own backend,
    /// and is only ever compared against itself.
    fun deviceUid(context: Context): String {
        val store = prefs(context)
        store.getString(DEVICE_UID, null)?.let { return it }
        val fresh = UUID.randomUUID().toString()
        store.edit().putString(DEVICE_UID, fresh).apply()
        return fresh
    }

    // -- storage --------------------------------------------------------------

    private fun prefs(context: Context): SharedPreferences =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun read(context: Context, key: String): String? =
        prefs(context).getString(key, null)?.let(::decrypt)

    // -- crypto ---------------------------------------------------------------

    private fun secretKey(): SecretKey {
        val keystore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keystore.getEntry(KEY_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }

        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .build()
        )
        return generator.generateKey()
    }

    /// The IV is generated by the cipher and stored in front of the ciphertext.
    /// GCM must never see the same IV twice under one key, so it is never
    /// chosen here.
    private fun encrypt(value: String): String? = try {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secretKey())
        val body = cipher.doFinal(value.toByteArray(Charsets.UTF_8))
        Base64.encodeToString(cipher.iv + body, Base64.NO_WRAP)
    } catch (e: Exception) {
        null
    }

    /// Returns null rather than throwing on a value this key can no longer open
    /// — a restored backup, or a keystore reset by a factory-reset-protection
    /// event. Dart reads that as "this device is not enrolled" and offers the
    /// button again, which is the only recovery there is.
    private fun decrypt(value: String): String? = try {
        val bytes = Base64.decode(value, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(
            Cipher.DECRYPT_MODE,
            secretKey(),
            GCMParameterSpec(GCM_TAG_BITS, bytes, 0, GCM_IV_BYTES),
        )
        String(cipher.doFinal(bytes, GCM_IV_BYTES, bytes.size - GCM_IV_BYTES), Charsets.UTF_8)
    } catch (e: Exception) {
        null
    }
}
