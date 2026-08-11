package org.codexnotif.server.entity;

import jakarta.persistence.*;
import java.time.Instant;

@Entity
@Table(
        name = "email_bindings",
        indexes = {
                @Index(name = "idx_bind_expiry", columnList = "expires_at")
        },
        uniqueConstraints = {
                @UniqueConstraint(name = "uk_bind_id", columnNames = "bind_id")
        })
public class EmailBindingEntity {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(name = "bind_id", nullable = false, length = 64)
    private String bindId;

    @Column(name = "device_id", nullable = false, length = 128)
    private String deviceId;

    @Column(nullable = false, length = 254)
    private String email;

    @Column(name = "poll_token_hash", nullable = false, length = 64)
    private String pollTokenHash;

    @Column(name = "verify_token_hash", nullable = false, length = 64)
    private String verifyTokenHash;

    @Column(name = "device_token_encrypted", length = 2048)
    private String deviceTokenEncrypted;

    @Column(nullable = false)
    private boolean verified;

    @Column(name = "created_at", nullable = false)
    private Instant createdAt;

    @Column(name = "expires_at", nullable = false)
    private Instant expiresAt;

    public Long getId() { return id; }

    public String getBindId() { return bindId; }
    public void setBindId(String bindId) { this.bindId = bindId; }

    public String getDeviceId() { return deviceId; }
    public void setDeviceId(String deviceId) { this.deviceId = deviceId; }

    public String getEmail() { return email; }
    public void setEmail(String email) { this.email = email; }

    public String getPollTokenHash() { return pollTokenHash; }
    public void setPollTokenHash(String pollTokenHash) { this.pollTokenHash = pollTokenHash; }

    public String getVerifyTokenHash() { return verifyTokenHash; }
    public void setVerifyTokenHash(String verifyTokenHash) { this.verifyTokenHash = verifyTokenHash; }

    public String getDeviceTokenEncrypted() { return deviceTokenEncrypted; }
    public void setDeviceTokenEncrypted(String deviceTokenEncrypted) { this.deviceTokenEncrypted = deviceTokenEncrypted; }

    public boolean isVerified() { return verified; }
    public void setVerified(boolean verified) { this.verified = verified; }

    public Instant getCreatedAt() { return createdAt; }
    public void setCreatedAt(Instant createdAt) { this.createdAt = createdAt; }

    public Instant getExpiresAt() { return expiresAt; }
    public void setExpiresAt(Instant expiresAt) { this.expiresAt = expiresAt; }
}
