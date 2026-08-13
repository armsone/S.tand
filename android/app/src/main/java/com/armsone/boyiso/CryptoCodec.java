package com.armsone.boyiso;

import org.json.JSONException;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;

import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

final class CryptoCodec {
    private static final SecureRandom RANDOM = new SecureRandom();
    private final SecretKeySpec key;

    CryptoCodec(String roomCode) {
        String normalized = roomCode.replaceAll("[^A-Za-z0-9]", "").toUpperCase();
        if (normalized.length() != 8) {
            throw new IllegalArgumentException("Room code must contain exactly 8 characters");
        }
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(("boyiso-v1|" + normalized).getBytes(StandardCharsets.UTF_8));
            key = new SecretKeySpec(digest, "AES");
        } catch (GeneralSecurityException error) {
            throw new IllegalStateException("Unable to derive room key", error);
        }
    }

    String sealToText(BoyisoEvent event) throws GeneralSecurityException {
        return Base64.getEncoder().encodeToString(seal(event.encodeBytes()));
    }

    byte[] sealEvent(BoyisoEvent event) throws GeneralSecurityException {
        return seal(event.encodeBytes());
    }

    private byte[] seal(byte[] cleartext) throws GeneralSecurityException {
        byte[] nonce = new byte[12];
        RANDOM.nextBytes(nonce);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key, new GCMParameterSpec(128, nonce));
        byte[] encrypted = cipher.doFinal(cleartext);
        byte[] output = Arrays.copyOf(nonce, nonce.length + encrypted.length);
        System.arraycopy(encrypted, 0, output, nonce.length, encrypted.length);
        return output;
    }

    BoyisoEvent openText(String encoded) throws GeneralSecurityException, JSONException {
        return openEvent(Base64.getDecoder().decode(encoded));
    }

    BoyisoEvent openEvent(byte[] payload) throws GeneralSecurityException, JSONException {
        return BoyisoEvent.decode(open(payload));
    }

    private byte[] open(byte[] payload) throws GeneralSecurityException {
        if (payload.length < 29) throw new GeneralSecurityException("Encrypted payload is too short");
        byte[] nonce = Arrays.copyOfRange(payload, 0, 12);
        byte[] encrypted = Arrays.copyOfRange(payload, 12, payload.length);
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key, new GCMParameterSpec(128, nonce));
        return cipher.doFinal(encrypted);
    }
}
