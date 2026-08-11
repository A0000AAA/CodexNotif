package org.codexnotif.server.service;

import org.springframework.stereotype.Service;
import org.codexnotif.server.config.AppProperties;
import org.codexnotif.server.model.EmailMessage;

@Service
public class EmailDispatchService {

    private final AppProperties properties;
    private final MicrosoftGraphEmailProvider microsoft;
    private final SmtpEmailProvider smtp;

    public EmailDispatchService(
            AppProperties properties,
            MicrosoftGraphEmailProvider microsoft,
            SmtpEmailProvider smtp) {
        this.properties = properties;
        this.microsoft = microsoft;
        this.smtp = smtp;
    }

    public void send(EmailMessage message) {
        String provider = properties.getEmail().getProvider();

        if ("microsoft".equalsIgnoreCase(provider)) {
            microsoft.send(message);
            return;
        }

        if ("smtp".equalsIgnoreCase(provider)) {
            smtp.send(message);
            return;
        }

        throw new IllegalStateException(
                "Unknown EMAIL_PROVIDER: " + provider);
    }
}
