package org.codexnotif.server.repository;

import org.springframework.data.jpa.repository.JpaRepository;
import org.codexnotif.server.entity.MicrosoftTokenEntity;

public interface MicrosoftTokenRepository
        extends JpaRepository<MicrosoftTokenEntity, Long> {
}
