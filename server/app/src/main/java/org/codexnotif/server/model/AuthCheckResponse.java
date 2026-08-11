package org.codexnotif.server.model;

public record AuthCheckResponse(
        boolean accessKeyAuthenticated,
        boolean deviceAuthenticated) {
}
