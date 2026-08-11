package org.codexnotif.server.security;

import jakarta.servlet.ServletException;
import org.codexnotif.server.config.AppProperties;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.IOException;

import static org.junit.jupiter.api.Assertions.assertEquals;

class AccessKeyFilterTest {

    private static final String ACCESS_KEY = "x".repeat(32);

    private AccessKeyFilter filter;

    @BeforeEach
    void setUp() {
        AppProperties properties = new AppProperties();
        properties.setAccessKey(ACCESS_KEY);
        filter = new AccessKeyFilter(new AccessKeyValidator(properties));
    }

    @Test
    void healthRejectsMissingKey() throws Exception {
        MockHttpServletResponse response = execute("/health", null);

        assertEquals(401, response.getStatus());
        assertEquals("application/json;charset=UTF-8", response.getContentType());
    }

    @Test
    void apiRejectsWrongKey() throws Exception {
        MockHttpServletResponse response = execute(
                "/api/v1/events", "y".repeat(32));

        assertEquals(401, response.getStatus());
    }

    @Test
    void protectedPathAllowsExactKey() throws Exception {
        MockHttpServletResponse response = execute("/health", ACCESS_KEY);

        assertEquals(200, response.getStatus());
    }

    @Test
    void exactBrowserVerificationPathRemainsPublic() throws Exception {
        MockHttpServletResponse response = execute(
                "/api/v1/bind/verify", null);

        assertEquals(200, response.getStatus());
    }

    @Test
    void similarVerificationPathIsStillProtected() throws Exception {
        MockHttpServletResponse response = execute(
                "/api/v1/bind/verify/extra", null);

        assertEquals(401, response.getStatus());
    }

    @Test
    void unrelatedPathIsNotFiltered() throws Exception {
        MockHttpServletResponse response = execute("/docs", null);

        assertEquals(200, response.getStatus());
    }

    private MockHttpServletResponse execute(String path, String key)
            throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
        if (key != null) {
            request.addHeader(AccessKeyValidator.HEADER_NAME, key);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }
}
