package org.codexnotif.server.service;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.springframework.stereotype.Service;
import org.codexnotif.server.model.EmailMessage;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

@Service
public class MicrosoftGraphEmailProvider {

    private final MicrosoftOAuthService oauth;
    private final ObjectMapper objectMapper;

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .build();

    public MicrosoftGraphEmailProvider(
            MicrosoftOAuthService oauth,
            ObjectMapper objectMapper) {
        this.oauth = oauth;
        this.objectMapper = objectMapper;
    }

    public void send(EmailMessage mail) {
        try {
            String accessToken = oauth.accessToken();

            ObjectNode root = objectMapper.createObjectNode();
            ObjectNode message = root.putObject("message");

            message.put("subject", mail.subject());

            ObjectNode body = message.putObject("body");
            body.put("contentType", "Text");
            body.put("content", mail.text());

            var recipients = message.putArray("toRecipients");
            ObjectNode recipient = recipients.addObject();
            recipient.putObject("emailAddress")
                    .put("address", mail.to());

            root.put("saveToSentItems", true);

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create("https://graph.microsoft.com/v1.0/me/sendMail"))
                    .timeout(Duration.ofSeconds(20))
                    .header("Authorization", "Bearer " + accessToken)
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(
                            objectMapper.writeValueAsString(root)))
                    .build();

            HttpResponse<String> response = http.send(
                    request,
                    HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() != 202) {
                throw new IllegalStateException(
                        "Microsoft Graph sendMail HTTP "
                                + response.statusCode()
                                + ": "
                                + response.body());
            }

        } catch (IllegalStateException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Microsoft Graph send failed: " + e.getMessage(),
                    e);
        }
    }
}
