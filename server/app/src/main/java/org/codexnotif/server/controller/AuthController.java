package org.codexnotif.server.controller;

import org.codexnotif.server.model.AuthCheckResponse;
import org.codexnotif.server.service.DeviceService;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

@RestController
@RequestMapping("/api/v1/auth")
public final class AuthController {

    private final DeviceService devices;

    public AuthController(DeviceService devices) {
        this.devices = devices;
    }

    @GetMapping("/check")
    public AuthCheckResponse check(
            @RequestParam String deviceId,
            @RequestHeader(
                    value = "Authorization",
                    required = false)
            String authorization) {
        boolean authenticated = devices.validate(
                deviceId,
                EventController.bearer(authorization));
        return new AuthCheckResponse(true, authenticated);
    }
}
