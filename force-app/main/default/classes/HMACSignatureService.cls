/**
 * @description Service class for HMAC signature generation and validation.
 *              Supports HmacSHA1, HmacSHA256, and HmacSHA512 algorithms using the
 *              platform Crypto.generateMac() method. Used for both outbound request
 *              signing and inbound webhook signature validation.
 *
 * @author Integration Platform
 * @date 2026-02-15
 */
public with sharing class HMACSignatureService {

    // ── Supported algorithms ──
    private static final Set<String> SUPPORTED_ALGORITHMS = new Set<String>{
        'HmacSHA1', 'hmacSHA1',
        'HmacSHA256', 'hmacSHA256',
        'HmacSHA512', 'hmacSHA512'
    };

    // ── Canonical algorithm names for Crypto.generateMac() ──
    private static final Map<String, String> ALGORITHM_MAP = new Map<String, String>{
        'hmacsha1'   => 'HmacSHA1',
        'hmacsha256' => 'HmacSHA256',
        'hmacsha512' => 'HmacSHA512'
    };

    // ─────────────────────────────────────────────────────────────────────────
    //  Public API
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Generates an HMAC signature for the given payload using the specified
     *              secret and algorithm. Returns the signature as a lowercase hex string.
     * @param payload   The message/body to sign. Null is treated as an empty string.
     * @param secret    The shared secret key. Must not be blank.
     * @param algorithm The HMAC algorithm (HmacSHA1, HmacSHA256, HmacSHA512).
     * @return Lowercase hex-encoded HMAC signature.
     * @throws HMACSignatureException on invalid inputs or unsupported algorithm.
     */
    public static String generateSignature(String payload, String secret, String algorithm) {
        validateInputs(secret, algorithm);

        String canonicalAlgorithm = resolveAlgorithm(algorithm);
        String safePayload = payload != null ? payload : '';

        Blob payloadBlob = Blob.valueOf(safePayload);
        Blob secretBlob = Blob.valueOf(secret);

        Blob signatureBlob;
        try {
            signatureBlob = Crypto.generateMac(canonicalAlgorithm, payloadBlob, secretBlob);
        } catch (Exception e) {
            throw new HMACSignatureException(
                'Failed to generate HMAC signature with algorithm ' + canonicalAlgorithm +
                ': ' + e.getMessage(), e
            );
        }

        return EncodingUtil.convertToHex(signatureBlob);
    }

    /**
     * @description Generates an HMAC signature using the default algorithm (HmacSHA256).
     * @param payload The message/body to sign.
     * @param secret  The shared secret key.
     * @return Lowercase hex-encoded HMAC signature.
     */
    public static String generateSignature(String payload, String secret) {
        return generateSignature(payload, secret, 'HmacSHA256');
    }

    /**
     * @description Validates that the provided signature matches the expected HMAC
     *              signature for the given payload, secret, and algorithm. Uses a
     *              constant-time comparison to mitigate timing attacks.
     * @param payload   The original message/body that was signed.
     * @param signature The signature to validate (hex-encoded).
     * @param secret    The shared secret key.
     * @param algorithm The HMAC algorithm used to generate the signature.
     * @return True if the signature is valid; false otherwise.
     */
    public static Boolean validateSignature(String payload, String signature, String secret, String algorithm) {
        if (String.isBlank(signature)) {
            return false;
        }

        try {
            String expectedSignature = generateSignature(payload, secret, algorithm);
            return constantTimeEquals(expectedSignature, signature.toLowerCase());
        } catch (Exception e) {
            // Log but don't propagate -- validation failure is not exceptional
            System.debug(LoggingLevel.WARN,
                'HMAC signature validation failed: ' + e.getMessage()
            );
            return false;
        }
    }

    /**
     * @description Validates a signature using the default algorithm (HmacSHA256).
     * @param payload   The original message/body.
     * @param signature The signature to validate.
     * @param secret    The shared secret key.
     * @return True if valid; false otherwise.
     */
    public static Boolean validateSignature(String payload, String signature, String secret) {
        return validateSignature(payload, signature, secret, 'HmacSHA256');
    }

    /**
     * @description Generates a signature using a Blob secret (for scenarios where the
     *              secret is binary / pre-encoded).
     * @param payload       The message/body to sign.
     * @param secretBlob    The secret as a Blob.
     * @param algorithm     The HMAC algorithm.
     * @return Lowercase hex-encoded HMAC signature.
     */
    public static String generateSignatureFromBlob(String payload, Blob secretBlob, String algorithm) {
        if (secretBlob == null) {
            throw new HMACSignatureException('Secret Blob cannot be null.');
        }
        if (String.isBlank(algorithm)) {
            throw new HMACSignatureException('Algorithm cannot be blank.');
        }

        String canonicalAlgorithm = resolveAlgorithm(algorithm);
        String safePayload = payload != null ? payload : '';

        Blob payloadBlob = Blob.valueOf(safePayload);

        Blob signatureBlob;
        try {
            signatureBlob = Crypto.generateMac(canonicalAlgorithm, payloadBlob, secretBlob);
        } catch (Exception e) {
            throw new HMACSignatureException(
                'Failed to generate HMAC signature from Blob: ' + e.getMessage(), e
            );
        }

        return EncodingUtil.convertToHex(signatureBlob);
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Validation & Utility
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Validates that the secret and algorithm are acceptable.
     */
    private static void validateInputs(String secret, String algorithm) {
        if (String.isBlank(secret)) {
            throw new HMACSignatureException('HMAC secret cannot be blank.');
        }
        if (String.isBlank(algorithm)) {
            throw new HMACSignatureException('HMAC algorithm cannot be blank.');
        }

        String normalised = algorithm.toLowerCase();
        if (!ALGORITHM_MAP.containsKey(normalised)) {
            throw new HMACSignatureException(
                'Unsupported HMAC algorithm: ' + algorithm +
                '. Supported algorithms: HmacSHA1, HmacSHA256, HmacSHA512.'
            );
        }
    }

    /**
     * @description Resolves a potentially case-variant algorithm name to the canonical
     *              form expected by Crypto.generateMac().
     */
    private static String resolveAlgorithm(String algorithm) {
        return ALGORITHM_MAP.get(algorithm.toLowerCase());
    }

    /**
     * @description Performs a constant-time string comparison to mitigate timing-based
     *              side-channel attacks during signature validation.
     * @param a First string.
     * @param b Second string.
     * @return True if both strings are equal.
     */
    @TestVisible
    private static Boolean constantTimeEquals(String a, String b) {
        if (a == null || b == null) {
            return a == b;
        }
        if (a.length() != b.length()) {
            return false;
        }

        Integer result = 0;
        for (Integer i = 0; i < a.length(); i++) {
            result |= a.charAt(i) ^ b.charAt(i);
        }
        return result == 0;
    }

    // ─────────────────────────────────────────────────────────────────────────
    //  Inner Classes
    // ─────────────────────────────────────────────────────────────────────────

    /**
     * @description Custom exception for HMAC signature failures.
     */
    public class HMACSignatureException extends Exception {}
}