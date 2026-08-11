package org.codexnotif.server.security;

import org.codexnotif.server.config.AppProperties;
import org.springframework.stereotype.Component;

@Component
public final class AccessKeyValidator {

    public static final String HEADER_NAME = "X-CodexNotif-Access-Key";
    private static final int MINIMUM_LENGTH = 32;

    private final String expectedHash;

    public AccessKeyValidator(AppProperties properties) {
        String key = properties.getAccessKey();
        if (key == null
                || key.length() < MINIMUM_LENGTH
                || !key.equals(key.trim())) {
            throw new IllegalStateException(
                    "CODEXNOTIF_ACCESS_KEY must contain at least 32 characters without surrounding whitespace.");
        }
        expectedHash = TokenUtil.sha256(key);
    }

    public boolean isValid(String supplied) {
        return supplied != null
                && !supplied.isBlank()
                && TokenUtil.constantTimeEquals(
                        expectedHash,
                        TokenUtil.sha256(supplied));
    }
}
