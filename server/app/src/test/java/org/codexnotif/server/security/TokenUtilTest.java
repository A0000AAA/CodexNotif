package org.codexnotif.server.security;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.*;

class TokenUtilTest {

    @Test
    void hashStable() {
        assertEquals(
                TokenUtil.sha256("abc"),
                TokenUtil.sha256("abc"));

        assertNotEquals(
                TokenUtil.sha256("abc"),
                TokenUtil.sha256("abcd"));
    }

    @Test
    void randomToken() {
        assertFalse(TokenUtil.randomToken(32).isBlank());
    }
}
