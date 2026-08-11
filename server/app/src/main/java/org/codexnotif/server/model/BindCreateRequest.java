package org.codexnotif.server.model;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public record BindCreateRequest(
        @NotBlank @Size(max = 128) String deviceId,
        @NotBlank @Email @Size(max = 254) String email
) {}
