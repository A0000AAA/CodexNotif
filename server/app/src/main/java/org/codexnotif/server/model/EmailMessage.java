package org.codexnotif.server.model;

public record EmailMessage(
        String to,
        String subject,
        String text
) {}
