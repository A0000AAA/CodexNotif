package org.codexnotif.server.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.codexnotif.server.entity.EmailBindingEntity;

import java.time.Instant;
import java.util.Optional;

public interface EmailBindingRepository
        extends JpaRepository<EmailBindingEntity, Long> {

    Optional<EmailBindingEntity> findByBindId(String bindId);

    long deleteByExpiresAtBefore(Instant instant);
}
