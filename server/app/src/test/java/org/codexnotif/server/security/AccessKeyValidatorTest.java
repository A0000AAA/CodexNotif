package org.codexnotif.server.security;

import org.codexnotif.server.config.AppProperties;
import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

class AccessKeyValidatorTest {

    @Test
    void missingKeyFailsClosed() {
        assertThrows(IllegalStateException.class,
                () -> new AccessKeyValidator(propertiesWith(null)));
    }

    @Test
    void shortKeyFailsClosed() {
        assertThrows(IllegalStateException.class,
                () -> new AccessKeyValidator(propertiesWith("short")));
    }

    @Test
    void surroundingWhitespaceFailsClosed() {
        assertThrows(IllegalStateException.class,
                () -> new AccessKeyValidator(
                        propertiesWith(" " + "x".repeat(32))));
    }

    @Test
    void exactKeyIsAcceptedAndDifferentKeyIsRejected() {
        String expected = "x".repeat(32);
        AccessKeyValidator validator = new AccessKeyValidator(
                propertiesWith(expected));

        assertTrue(validator.isValid(expected));
        assertFalse(validator.isValid("y".repeat(32)));
        assertFalse(validator.isValid(null));
    }

    private static AppProperties propertiesWith(String value) {
        AppProperties properties = new AppProperties();
        properties.setAccessKey(value);
        return properties;
    }
}
