package org.codexnotif.server.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.codexnotif.server.config.AppProperties;
import org.codexnotif.server.entity.MicrosoftTokenEntity;
import org.codexnotif.server.repository.MicrosoftTokenRepository;
import org.codexnotif.server.security.CryptoService;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Service
public class MicrosoftOAuthService {

    private final AppProperties properties;
    private final MicrosoftTokenRepository tokenRepository;
    private final CryptoService crypto;
    private final ObjectMapper objectMapper;

    private final HttpClient http = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(8))
            .build();

    private final Map<String, Instant> states = new ConcurrentHashMap<>();

    public MicrosoftOAuthService(
            AppProperties properties,
            MicrosoftTokenRepository tokenRepository,
            CryptoService crypto,
            ObjectMapper objectMapper) {
        this.properties = properties;
        this.tokenRepository = tokenRepository;
        this.crypto = crypto;
        this.objectMapper = objectMapper;
    }

    public String createAuthorizationUrl() {
        ensureConfigured();

        String state = org.codexnotif.server.security.TokenUtil.randomToken(24);
        states.put(state, Instant.now().plusSeconds(600));

        var ms = properties.getEmail().getMicrosoft();

        String scope = "offline_access https://graph.microsoft.com/Mail.Send";

        return "https://login.microsoftonline.com/"
                + enc(ms.getTenant())
                + "/oauth2/v2.0/authorize"
                + "?client_id=" + enc(ms.getClientId())
                + "&response_type=code"
                + "&redirect_uri=" + enc(ms.getRedirectUri())
                + "&response_mode=query"
                + "&scope=" + enc(scope)
                + "&state=" + enc(state);
    }

    public void acceptCallback(String code, String state) {
        ensureConfigured();

        Instant expiry = states.remove(state);

        if (expiry == null || expiry.isBefore(Instant.now())) {
            throw new IllegalStateException("Invalid or expired OAuth state.");
        }

        JsonNode token = requestToken(Map.of(
                "client_id", properties.getEmail().getMicrosoft().getClientId(),
                "client_secret", properties.getEmail().getMicrosoft().getClientSecret(),
                "grant_type", "authorization_code",
                "code", code,
                "redirect_uri", properties.getEmail().getMicrosoft().getRedirectUri(),
                "scope", "offline_access https://graph.microsoft.com/Mail.Send"
        ));

        String refresh = token.path("refresh_token").asText();

        if (refresh.isBlank()) {
            throw new IllegalStateException(
                    "Microsoft did not return a refresh_token. Ensure offline_access consent is allowed.");
        }

        saveRefreshToken(refresh);
    }

    public String accessToken() {
        ensureConfigured();

        MicrosoftTokenEntity entity = tokenRepository.findById(1L)
                .orElseThrow(() -> new IllegalStateException(
                        "Microsoft mailbox is not connected. Open /admin/microsoft/connect first."));

        String refresh = crypto.decrypt(entity.getRefreshTokenEncrypted());

        JsonNode token = requestToken(Map.of(
                "client_id", properties.getEmail().getMicrosoft().getClientId(),
                "client_secret", properties.getEmail().getMicrosoft().getClientSecret(),
                "grant_type", "refresh_token",
                "refresh_token", refresh,
                "scope", "offline_access https://graph.microsoft.com/Mail.Send"
        ));

        String access = token.path("access_token").asText();

        if (access.isBlank()) {
            throw new IllegalStateException("Microsoft access_token is empty.");
        }

        String rotated = token.path("refresh_token").asText();

        if (!rotated.isBlank() && !rotated.equals(refresh)) {
            saveRefreshToken(rotated);
        }

        return access;
    }

    public boolean isConnected() {
        return tokenRepository.existsById(1L);
    }

    private void saveRefreshToken(String refresh) {
        MicrosoftTokenEntity entity = new MicrosoftTokenEntity();
        entity.setId(1L);
        entity.setRefreshTokenEncrypted(crypto.encrypt(refresh));
        entity.setUpdatedAt(Instant.now());
        tokenRepository.save(entity);
    }

    private JsonNode requestToken(Map<String, String> fields) {
        try {
            StringBuilder form = new StringBuilder();

            for (var entry : fields.entrySet()) {
                if (entry.getValue() == null || entry.getValue().isBlank()) continue;

                if (!form.isEmpty()) form.append('&');

                form.append(enc(entry.getKey()))
                        .append('=')
                        .append(enc(entry.getValue()));
            }

            String url = "https://login.microsoftonline.com/"
                    + enc(properties.getEmail().getMicrosoft().getTenant())
                    + "/oauth2/v2.0/token";

            HttpRequest request = HttpRequest.newBuilder()
                    .uri(URI.create(url))
                    .timeout(Duration.ofSeconds(15))
                    .header(
                            "Content-Type",
                            MediaType.APPLICATION_FORM_URLENCODED_VALUE)
                    .POST(HttpRequest.BodyPublishers.ofString(form.toString()))
                    .build();

            HttpResponse<String> response = http.send(
                    request,
                    HttpResponse.BodyHandlers.ofString());

            JsonNode json = objectMapper.readTree(response.body());

            if (response.statusCode() / 100 != 2) {
                throw new IllegalStateException(
                        "Microsoft token error: "
                                + json.path("error").asText()
                                + " / "
                                + json.path("error_description").asText());
            }

            return json;

        } catch (IllegalStateException e) {
            throw e;
        } catch (Exception e) {
            throw new IllegalStateException(
                    "Microsoft token request failed: " + e.getMessage(),
                    e);
        }
    }

    private void ensureConfigured() {
        var ms = properties.getEmail().getMicrosoft();

        if (!ms.isEnabled()) {
            throw new IllegalStateException("MICROSOFT_ENABLED=false");
        }

        if (blank(ms.getClientId())
                || blank(ms.getClientSecret())
                || blank(ms.getRedirectUri())) {
            throw new IllegalStateException(
                    "MICROSOFT_CLIENT_ID / MICROSOFT_CLIENT_SECRET / MICROSOFT_REDIRECT_URI is incomplete.");
        }
    }

    private static boolean blank(String s) {
        return s == null || s.isBlank();
    }

    private static String enc(String s) {
        return URLEncoder.encode(
                s == null ? "" : s,
                StandardCharsets.UTF_8);
    }
}
