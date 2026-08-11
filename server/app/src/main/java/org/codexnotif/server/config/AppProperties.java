package org.codexnotif.server.config;

import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.stereotype.Component;

@Component
@ConfigurationProperties(prefix = "app")
public class AppProperties {

    private String publicBaseUrl;
    private int bindTtlSeconds = 600;
    private String notificationMode = "email";
    private String encryptionKey;
    private String adminSetupToken;

    private final Email email = new Email();

    public String getPublicBaseUrl() { return publicBaseUrl; }
    public void setPublicBaseUrl(String publicBaseUrl) { this.publicBaseUrl = publicBaseUrl; }

    public int getBindTtlSeconds() { return bindTtlSeconds; }
    public void setBindTtlSeconds(int bindTtlSeconds) { this.bindTtlSeconds = bindTtlSeconds; }

    public String getNotificationMode() { return notificationMode; }
    public void setNotificationMode(String notificationMode) { this.notificationMode = notificationMode; }

    public String getEncryptionKey() { return encryptionKey; }
    public void setEncryptionKey(String encryptionKey) { this.encryptionKey = encryptionKey; }

    public String getAdminSetupToken() { return adminSetupToken; }
    public void setAdminSetupToken(String adminSetupToken) { this.adminSetupToken = adminSetupToken; }

    public Email getEmail() { return email; }

    public static class Email {
        private String provider = "microsoft";
        private String fromName = "Agent Pager";
        private String subjectPrefix = "[Agent Pager]";
        private final Smtp smtp = new Smtp();
        private final Microsoft microsoft = new Microsoft();

        public String getProvider() { return provider; }
        public void setProvider(String provider) { this.provider = provider; }

        public String getFromName() { return fromName; }
        public void setFromName(String fromName) { this.fromName = fromName; }

        public String getSubjectPrefix() { return subjectPrefix; }
        public void setSubjectPrefix(String subjectPrefix) { this.subjectPrefix = subjectPrefix; }

        public Smtp getSmtp() { return smtp; }
        public Microsoft getMicrosoft() { return microsoft; }
    }

    public static class Smtp {
        private String from;

        public String getFrom() { return from; }
        public void setFrom(String from) { this.from = from; }
    }

    public static class Microsoft {
        private boolean enabled;
        private String tenant = "common";
        private String clientId;
        private String clientSecret;
        private String redirectUri;

        public boolean isEnabled() { return enabled; }
        public void setEnabled(boolean enabled) { this.enabled = enabled; }

        public String getTenant() { return tenant; }
        public void setTenant(String tenant) { this.tenant = tenant; }

        public String getClientId() { return clientId; }
        public void setClientId(String clientId) { this.clientId = clientId; }

        public String getClientSecret() { return clientSecret; }
        public void setClientSecret(String clientSecret) { this.clientSecret = clientSecret; }

        public String getRedirectUri() { return redirectUri; }
        public void setRedirectUri(String redirectUri) { this.redirectUri = redirectUri; }
    }
}
