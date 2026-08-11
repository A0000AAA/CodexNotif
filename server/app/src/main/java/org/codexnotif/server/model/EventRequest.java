package org.codexnotif.server.model;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import java.time.OffsetDateTime;

public record EventRequest(
        @NotBlank @Size(max = 128) String deviceId,
        @NotBlank @Size(max = 64) String source,
        @NotBlank @Size(max = 64) String event,
        @NotNull OffsetDateTime timestamp
) {}
