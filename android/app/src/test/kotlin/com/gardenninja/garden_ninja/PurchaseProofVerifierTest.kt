package com.gardenninja.garden_ninja

import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class PurchaseProofVerifierTest {
    private val keys = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()

    private fun receipt(): JSONObject = JSONObject()
        .put("packageName", PurchaseProofVerifier.appPackage)
        .put("productId", PurchaseProofVerifier.productId)
        .put("purchaseState", 0)
        .put("purchaseTime", 1700000000000L)
        .put("purchaseToken", "test-token-never-sent-to-a-store")

    private fun sign(data: String): ByteArray = Signature.getInstance("SHA1withRSA").run {
        initSign(keys.private)
        update(data.toByteArray(Charsets.UTF_8))
        sign()
    }

    private fun verify(value: JSONObject): Boolean {
        val data = value.toString()
        return PurchaseProofVerifier.verify(data, sign(data), keys.public.encoded)
    }

    @Test fun validProofAndProductArrayAreAccepted() {
        assertTrue(verify(receipt()))
        val arrayReceipt = receipt().apply { remove("productId"); put("productIds", listOf(PurchaseProofVerifier.productId)) }
        assertTrue(verify(arrayReceipt))
    }

    @Test fun tamperedProofAndWrongKeyAreRejected() {
        val original = receipt().toString()
        val changed = receipt().put("purchaseTime", 1700000000001L).toString()
        assertFalse(PurchaseProofVerifier.verify(changed, sign(original), keys.public.encoded))
        val other = KeyPairGenerator.getInstance("RSA").apply { initialize(2048) }.generateKeyPair()
        assertFalse(PurchaseProofVerifier.verify(original, sign(original), other.public.encoded))
        assertFalse(PurchaseProofVerifier.verify(original, byteArrayOf(), keys.public.encoded))
    }

    @Test fun anotherAppOrProductCannotGrantGardenEntitlement() {
        assertFalse(verify(receipt().put("packageName", "com.example.other")))
        assertFalse(verify(receipt().put("productId", "another_product")))
    }

    @Test fun pendingCancelledOrIncompleteProofsAreRejected() {
        for (state in listOf(1, 2, 4)) assertFalse(verify(receipt().put("purchaseState", state)))
        assertFalse(verify(receipt().apply { remove("purchaseState") }))
        assertFalse(verify(receipt().put("purchaseTime", 0)))
        assertFalse(verify(receipt().put("purchaseToken", "")))
    }

    @Test fun productionPublicKeyIsAValidRsaVerificationKey() {
        val key = KeyFactory.getInstance("RSA").generatePublic(
            X509EncodedKeySpec(Base64.getDecoder().decode(PurchaseProofVerifier.publicKey))
        )
        assertEquals("RSA", key.algorithm)
        // Test signatures must never validate against Google's production key.
        val data = receipt().toString()
        assertFalse(PurchaseProofVerifier.verify(data, sign(data), key.encoded))
    }
}
