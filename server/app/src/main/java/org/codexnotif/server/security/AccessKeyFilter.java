package org.codexnotif.server.security;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;

@Component
public final class AccessKeyFilter extends OncePerRequestFilter {

    private static final String PUBLIC_BIND_VERIFY = "/api/v1/bind/verify";

    private final AccessKeyValidator validator;

    public AccessKeyFilter(AccessKeyValidator validator) {
        this.validator = validator;
    }

    @Override
    protected boolean shouldNotFilter(HttpServletRequest request) {
        String path = request.getRequestURI();
        if (PUBLIC_BIND_VERIFY.equals(path)) {
            return true;
        }
        return !"/health".equals(path) && !path.startsWith("/api/v1/");
    }

    @Override
    protected void doFilterInternal(
            HttpServletRequest request,
            HttpServletResponse response,
            FilterChain filterChain) throws ServletException, IOException {
        if (!validator.isValid(request.getHeader(AccessKeyValidator.HEADER_NAME))) {
            response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
            response.setCharacterEncoding(StandardCharsets.UTF_8.name());
            response.setContentType("application/json");
            response.getWriter().write("{\"error\":\"unauthorized\"}");
            return;
        }

        filterChain.doFilter(request, response);
    }
}
