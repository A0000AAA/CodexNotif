package org.codexnotif.server.model;

import java.time.Instant;

public record BindCreateResponse(
        String bindId,
        String pollToken,
        Instant expiresAt
) {}
