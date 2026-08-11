package org.codexnotif.server.security;

import jakarta.annotation.PostConstruct;
import org.springframework.stereotype.Service;
import org.codexnotif.server.config.AppProperties;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.Base64;

@Service
public class CryptoService {

    private static final SecureRandom RANDOM = new SecureRandom();

    private final AppProperties properties;
    private SecretKeySpec key;

    public CryptoService(AppProperties properties) {
        this.properties = properties;
    }

    @PostConstruct
    void init() {
        String encoded = properties.getEncryptionKey();

        if (encoded == null || encoded.isBlank()) {
            throw new IllegalStateException(
                    "APP_ENCRYPTION_KEY is required. Use a Base64 encoded 32-byte random key.");
        }

        byte[] raw;

        try {
            raw = Base64.getDecoder().decode(encoded);
        } catch (Exception e) {
            throw new IllegalStateException("APP_ENCRYPTION_KEY must be Base64.", e);
        }

        if (raw.length != 32) {
            throw new IllegalStateException(
                    "APP_ENCRYPTION_KEY must decode to exactly 32 bytes.");
        }

        key = new SecretKeySpec(raw, "AES");
    }

    public String encrypt(String plainText) {
        try {
            byte[] iv = new byte[12];
            RANDOM.nextBytes(iv);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(
                    Cipher.ENCRYPT_MODE,
                    key,
                    new GCMParameterSpec(128, iv));

            byte[] encrypted = cipher.doFinal(
                    plainText.getBytes(StandardCharsets.UTF_8));

            byte[] result = new byte[iv.length + encrypted.length];

            System.arraycopy(iv, 0, result, 0, iv.length);
            System.arraycopy(encrypted, 0, result, iv.length, encrypted.length);

            return Base64.getEncoder().encodeToString(result);

        } catch (Exception e) {
            throw new IllegalStateException("Encryption failed.", e);
        }
    }

    public String decrypt(String cipherText) {
        try {
            byte[] all = Base64.getDecoder().decode(cipherText);

            if (all.length < 13) {
                throw new IllegalArgumentException("Invalid encrypted data.");
            }

            byte[] iv = new byte[12];
            byte[] encrypted = new byte[all.length - 12];

            System.arraycopy(all, 0, iv, 0, 12);
            System.arraycopy(all, 12, encrypted, 0, encrypted.length);

            Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
            cipher.init(
                    Cipher.DECRYPT_MODE,
                    key,
                    new GCMParameterSpec(128, iv));

            return new String(
                    cipher.doFinal(encrypted),
                    StandardCharsets.UTF_8);

        } catch (Exception e) {
            throw new IllegalStateException("Decryption failed.", e);
        }
    }
}
