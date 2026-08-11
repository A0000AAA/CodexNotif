package org.codexnotif.server.service;

import jakarta.mail.internet.InternetAddress;
import jakarta.mail.internet.MimeMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;
import org.codexnotif.server.config.AppProperties;
import org.codexnotif.server.model.EmailMessage;

import java.nio.charset.StandardCharsets;

@Service
public class SmtpEmailProvider {

    private final JavaMailSender mailSender;
    private final AppProperties properties;

    public SmtpEmailProvider(
            JavaMailSender mailSender,
            AppProperties properties) {
        this.mailSender = mailSender;
        this.properties = properties;
    }

    public void send(EmailMessage mail) {
        try {
            String from = properties.getEmail().getSmtp().getFrom();

            if (from == null || from.isBlank()) {
                throw new IllegalStateException("SMTP_FROM is empty.");
            }

            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(
                    message,
                    false,
                    StandardCharsets.UTF_8.name());

            helper.setTo(mail.to());

            String fromName = properties.getEmail().getFromName();

            if (fromName != null && !fromName.isBlank()) {
                helper.setFrom(new InternetAddress(
                        from,
                        fromName,
                        StandardCharsets.UTF_8.name()));
            } else {
                helper.setFrom(from);
            }

            helper.setSubject(mail.subject());
            helper.setText(mail.text(), false);

            mailSender.send(message);

        } catch (Exception e) {
            throw new IllegalStateException(
                    "SMTP send failed: " + e.getMessage(),
                    e);
        }
    }
}
