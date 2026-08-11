package org.codexnotif.server.service;

import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.codexnotif.server.config.AppProperties;
import org.codexnotif.server.entity.EmailBindingEntity;
import org.codexnotif.server.model.EmailMessage;
import org.codexnotif.server.repository.EmailBindingRepository;
import org.codexnotif.server.security.CryptoService;
import org.codexnotif.server.security.TokenUtil;

import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Optional;

@Service
public class BindingService {

    private final EmailBindingRepository bindings;
    private final DeviceService devices;
    private final EmailDispatchService email;
    private final CryptoService crypto;
    private final AppProperties properties;

    public BindingService(
            EmailBindingRepository bindings,
            DeviceService devices,
            EmailDispatchService email,
            CryptoService crypto,
            AppProperties properties) {
        this.bindings = bindings;
        this.devices = devices;
        this.email = email;
        this.crypto = crypto;
        this.properties = properties;
    }

    @Transactional
    public CreatedBinding create(String deviceId, String address) {
        String bindId = TokenUtil.randomToken(12);
        String pollToken = TokenUtil.randomToken(24);
        String verifyToken = TokenUtil.randomToken(24);

        Instant now = Instant.now();
        Instant expiresAt = now.plusSeconds(properties.getBindTtlSeconds());

        EmailBindingEntity entity = new EmailBindingEntity();
        entity.setBindId(bindId);
        entity.setDeviceId(deviceId);
        entity.setEmail(address);
        entity.setPollTokenHash(TokenUtil.sha256(pollToken));
        entity.setVerifyTokenHash(TokenUtil.sha256(verifyToken));
        entity.setVerified(false);
        entity.setCreatedAt(now);
        entity.setExpiresAt(expiresAt);

        bindings.save(entity);

        String base =
                properties.getPublicBaseUrl().replaceAll("/+$", "");

        String verifyUrl =
                base
                        + "/api/v1/bind/verify"
                        + "?bindId=" + enc(bindId)
                        + "&verifyToken=" + enc(verifyToken);

        String subject =
                properties.getEmail().getSubjectPrefix()
                        + " 验证邮箱绑定";

        int minutes =
                Math.max(1, properties.getBindTtlSeconds() / 60);

        String text =
                "你正在绑定 CodexNotif。"
                        + "\n\n请在 "
                        + minutes
                        + " 分钟内打开下面的链接完成验证："
                        + "\n\n"
                        + verifyUrl
                        + "\n\n如果不是你本人操作，请忽略本邮件。";

        try {
            email.send(new EmailMessage(
                    address,
                    subject,
                    text));
        } catch (RuntimeException e) {
            bindings.delete(entity);
            throw e;
        }

        return new CreatedBinding(
                bindId,
                pollToken,
                expiresAt);
    }

    public Optional<EmailBindingEntity> getAuthorized(
            String bindId,
            String pollToken) {

        if (pollToken == null || pollToken.isBlank()) {
            return Optional.empty();
        }

        return bindings.findByBindId(bindId)
                .filter(b -> b.getExpiresAt().isAfter(Instant.now()))
                .filter(b -> TokenUtil.constantTimeEquals(
                        b.getPollTokenHash(),
                        TokenUtil.sha256(pollToken)));
    }

    @Transactional
    public boolean verify(
            String bindId,
            String verifyToken) {

        EmailBindingEntity binding =
                bindings.findByBindId(bindId)
                        .orElse(null);

        if (binding == null
                || binding.getExpiresAt().isBefore(Instant.now())
                || verifyToken == null
                || !TokenUtil.constantTimeEquals(
                        binding.getVerifyTokenHash(),
                        TokenUtil.sha256(verifyToken))) {
            return false;
        }

        if (!binding.isVerified()) {
            String rawDeviceToken =
                    TokenUtil.randomToken(32);

            devices.bind(
                    binding.getDeviceId(),
                    binding.getEmail(),
                    rawDeviceToken);

            binding.setDeviceTokenEncrypted(
                    crypto.encrypt(rawDeviceToken));

            binding.setVerified(true);
            bindings.save(binding);
        }

        return true;
    }

    public String decryptedDeviceToken(
            EmailBindingEntity binding) {

        if (!binding.isVerified()
                || binding.getDeviceTokenEncrypted() == null) {
            return null;
        }

        return crypto.decrypt(
                binding.getDeviceTokenEncrypted());
    }

    @Scheduled(fixedDelay = 60000)
    @Transactional
    public void cleanupExpired() {
        bindings.deleteByExpiresAtBefore(
                Instant.now().minusSeconds(60));
    }

    private static String enc(String value) {
        return URLEncoder.encode(
                value,
                StandardCharsets.UTF_8);
    }

    public record CreatedBinding(
            String bindId,
            String pollToken,
            Instant expiresAt) {
    }
}
