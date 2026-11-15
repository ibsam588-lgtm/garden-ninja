package com.gardenninja.garden_ninja

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import org.json.JSONObject

/** Validate Google's signed purchase bytes before any local ad-free entitlement. */
internal object PurchaseProofVerifier {
    const val productId = "garden_ninja_remove_ads"
    const val appPackage = "com.gardenninja.garden_ninja"

    // Public app-licensing verification key from Garden Ninja's Play Console.
    // This is intentionally shipped in the app; it is not an API/private key.
    const val publicKey = "MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAzHekdUUGPaINfgQB8EBAj4lSVpi7rw+UAR/Aq+1+GuA1S8T2LdlqHQ3z4GoiTB+Gp2e39U0xSd5jn7h52yZt0XTwvW//ErvY8gjBphdo5iwyIlhOna8KbjTfSrtF3o2K9y4heKOoe1vWv12Phfplx83EEbY7Dvcc2DWKMdkOJJZlRN+VsHeLJevWsKKJJouT4qv4RVNUR9m59x9mG0cVKZDpjkwEws+8pcsqgHTrUapD3nDqCmt/JXti8ZgGrE/RtyJm3M4YsOacIH4JAAlf64xG3JbhLZysG0pZQLiJj2bITCFSy2Xl1ec/DwzS14+tPj/WnDMxvWKQTZcqwojHmQIDAQAB"

    fun verify(data: String, signature: ByteArray, keyDer: ByteArray): Boolean = try {
        val key = KeyFactory.getInstance("RSA").generatePublic(X509EncodedKeySpec(keyDer))
        val verifier = Signature.getInstance("SHA1withRSA")
        verifier.initVerify(key)
        verifier.update(data.toByteArray(Charsets.UTF_8))
        if (!verifier.verify(signature)) {
            false
        } else {
            val receipt = JSONObject(data)
            val products = receipt.optJSONArray("productIds")
            val matchesProduct = receipt.optString("productId") == productId ||
                (products != null && (0 until products.length()).any { products.optString(it) == productId })
            val token = receipt.optString("purchaseToken").ifBlank { receipt.optString("token") }
            receipt.optString("packageName") == appPackage && matchesProduct &&
                receipt.has("purchaseState") && receipt.optInt("purchaseState", -1) == 0 &&
                receipt.optLong("purchaseTime", 0) > 0 && token.isNotBlank()
        }
    } catch (_: Exception) {
        false
    }
}
