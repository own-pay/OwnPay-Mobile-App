package org.ownpay.console

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.security.SecureRandom
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import android.util.Base64

/**
 * Encrypts the on-device SMS capture buffer at rest.
 *
 * The key is generated inside the Android Keystore (non-exportable) under [KEY_ALIAS] with
 * AES-256-GCM and no padding. The ciphertext layout is base64(iv || ciphertext||tag) which is
 * what [readBufferArray] stores after the `v2:` marker.
 *
 * Nothing here ever leaves the device; the Keystore key material is never serialized. If the key
 * is lost (e.g. app data wiped on another flavor), the buffer can no longer be decrypted and is
 * dropped at the earliest opportunity — that is the same failure mode as any lost Keystore key,
 * and the app degrades to "empty buffer" rather than crashing.
 */
object SmsBufferCrypto {
    const val KEY_ALIAS = "ownpay_sms_buffer_key"

    private const val IV_LENGTH_BYTES = 12
    private const val TAG_LENGTH_BITS = 128
    private const val AES_TRANSFORM = "AES/GCM/NoPadding"

    fun encryptBuffer(plainText: String): String {
        val cipher = Cipher.getInstance(AES_TRANSFORM)
        cipher.init(
            Cipher.ENCRYPT_MODE,
            secretKey(),
            GCMParameterSpec(TAG_LENGTH_BITS, randomIv())
        )
        val bytes = cipher.doFinal(plainText.toByteArray(Charsets.UTF_8))
        val ivAndBody = cipher.iv + bytes
        return Base64.encodeToString(ivAndBody, Base64.NO_WRAP)
    }

    fun decryptBuffer(stored: String): String {
        val packed = Base64.decode(stored, Base64.NO_WRAP)
        require(packed.size > IV_LENGTH_BYTES) { "buffer payload too short" }
        val iv = packed.copyOfRange(0, IV_LENGTH_BYTES)
        val body = packed.copyOfRange(IV_LENGTH_BYTES, packed.size)

        val cipher = Cipher.getInstance(AES_TRANSFORM)
        cipher.init(Cipher.DECRYPT_MODE, secretKey(), GCMParameterSpec(TAG_LENGTH_BITS, iv))
        return String(cipher.doFinal(body), Charsets.UTF_8)
    }

    private fun randomIv(): ByteArray =
        ByteArray(IV_LENGTH_BYTES).also { SecureRandom().nextBytes(it) }

    private fun secretKey(): SecretKey {
        val keyStore = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }

        val generator = KeyGenerator.getInstance("AES", "AndroidKeyStore")
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return generator.generateKey()
    }
}
