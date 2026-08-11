package org.codexnotif.server.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.codexnotif.server.entity.DeviceEntity;

import java.util.Optional;

public interface DeviceRepository extends JpaRepository<DeviceEntity, Long> {
    Optional<DeviceEntity> findByDeviceId(String deviceId);
    boolean existsByDeviceId(String deviceId);
}
