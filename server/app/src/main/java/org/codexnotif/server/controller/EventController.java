package org.codexnotif.server.controller;

import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.codexnotif.server.model.ApiResponse;
import org.codexnotif.server.model.EventRequest;
import org.codexnotif.server.service.DeviceService;
import org.codexnotif.server.service.NotificationService;
import org.codexnotif.server.service.SimpleRateLimiter;

@RestController
@RequestMapping("/api/v1/events")
public class EventController {

    private final DeviceService devices;
    private final NotificationService notifications;
    private final SimpleRateLimiter limiter;

    public EventController(
            DeviceService devices,
            NotificationService notifications,
            SimpleRateLimiter limiter) {
        this.devices = devices;
        this.notifications = notifications;
        this.limiter = limiter;
    }

    @PostMapping
    public ResponseEntity<ApiResponse> receive(
            @RequestHeader(
                    value = "Authorization",
                    required = false)
            String authorization,
            @Valid @RequestBody EventRequest event) {

        String token = bearer(authorization);

        if (!devices.validate(event.deviceId(), token)) {
            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(ApiResponse.fail("Invalid device token."));
        }

        if (!limiter.allow(
                "event:" + event.deviceId(),
                30,
                60)) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .body(ApiResponse.fail("Too many events."));
        }

        var device = devices.find(event.deviceId())
                .orElseThrow();

        notifications.notify(device, event);

        return ResponseEntity.ok(
                ApiResponse.ok("Event accepted."));
    }

    static String bearer(String authorization) {
        if (authorization == null) return null;

        String prefix = "Bearer ";

        if (!authorization.regionMatches(
                true,
                0,
                prefix,
                0,
                prefix.length())) {
            return null;
        }

        return authorization.substring(prefix.length()).trim();
    }
}
