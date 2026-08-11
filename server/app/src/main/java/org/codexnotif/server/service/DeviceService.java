package org.codexnotif.server.service;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.codexnotif.server.entity.DeviceEntity;
import org.codexnotif.server.repository.DeviceRepository;
import org.codexnotif.server.security.TokenUtil;

import java.time.Instant;
import java.util.Optional;

@Service
public class DeviceService {

    private final DeviceRepository repository;

    public DeviceService(DeviceRepository repository) {
        this.repository = repository;
    }

    public boolean exists(String deviceId) {
        return repository.existsByDeviceId(deviceId);
    }

    public Optional<DeviceEntity> find(String deviceId) {
        return repository.findByDeviceId(deviceId);
    }

    public boolean validate(String deviceId, String rawToken) {
        if (rawToken == null || rawToken.isBlank()) return false;

        return repository.findByDeviceId(deviceId)
                .map(device -> TokenUtil.constantTimeEquals(
                        device.getTokenHash(),
                        TokenUtil.sha256(rawToken)))
                .orElse(false);
    }

    @Transactional
    public void bind(String deviceId, String email, String rawToken) {
        Instant now = Instant.now();

        DeviceEntity device = repository.findByDeviceId(deviceId)
                .orElseGet(DeviceEntity::new);

        if (device.getCreatedAt() == null) {
            device.setCreatedAt(now);
        }

        device.setDeviceId(deviceId);
        device.setEmail(email);
        device.setTokenHash(TokenUtil.sha256(rawToken));
        device.setUpdatedAt(now);

        repository.save(device);
    }
}
