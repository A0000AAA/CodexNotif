package org.codexnotif.server.service;

import org.codexnotif.server.model.EmailMessage;

public interface EmailProvider {
    void send(EmailMessage message);
}
