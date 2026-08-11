package org.codexnotif.server.controller;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.codexnotif.server.model.*;
import org.codexnotif.server.service.BindingService;
import org.codexnotif.server.service.DeviceService;
import org.codexnotif.server.service.SimpleRateLimiter;

@RestController
@RequestMapping("/api/v1/bind")
public class BindController {

    private final BindingService bindings;
    private final DeviceService devices;
    private final SimpleRateLimiter limiter;

    public BindController(
            BindingService bindings,
            DeviceService devices,
            SimpleRateLimiter limiter) {
        this.bindings = bindings;
        this.devices = devices;
        this.limiter = limiter;
    }

    @PostMapping("/create")
    public ResponseEntity<?> create(
            @RequestHeader(
                    value = "Authorization",
                    required = false)
            String authorization,
            @Valid @RequestBody BindCreateRequest request,
            HttpServletRequest http) {

        String ip = realIp(http);

        if (!limiter.allow("bind:" + ip, 10, 600)) {
            return ResponseEntity.status(HttpStatus.TOO_MANY_REQUESTS)
                    .body(ApiResponse.fail("Too many bind requests."));
        }

        // Existing device rebind requires the old device token.
        if (devices.exists(request.deviceId())
                && !devices.validate(
                        request.deviceId(),
                        EventController.bearer(authorization))) {

            return ResponseEntity.status(HttpStatus.UNAUTHORIZED)
                    .body(ApiResponse.fail(
                            "Rebind requires current device token."));
        }

        try {
            var created = bindings.create(
                    request.deviceId(),
                    request.email());

            return ResponseEntity.ok(
                    new BindCreateResponse(
                            created.bindId(),
                            created.pollToken(),
                            created.expiresAt()));

        } catch (Exception e) {
            return ResponseEntity.status(HttpStatus.BAD_GATEWAY)
                    .body(ApiResponse.fail(e.getMessage()));
        }
    }

    @GetMapping("/{bindId}")
    public ResponseEntity<?> status(
            @PathVariable String bindId,
            @RequestParam String pollToken) {

        var binding = bindings.getAuthorized(
                bindId,
                pollToken);

        if (binding.isEmpty()) {
            return ResponseEntity.status(HttpStatus.NOT_FOUND)
                    .body(ApiResponse.fail(
                            "Binding session not found or expired."));
        }

        var entity = binding.get();

        if (!entity.isVerified()) {
            return ResponseEntity.ok(
                    BindStatusResponse.pending(
                            entity.getEmail()));
        }

        return ResponseEntity.ok(
                BindStatusResponse.bound(
                        bindings.decryptedDeviceToken(entity),
                        entity.getEmail()));
    }

    @GetMapping(
            value = "/verify",
            produces = MediaType.TEXT_HTML_VALUE)
    public ResponseEntity<String> verify(
            @RequestParam String bindId,
            @RequestParam String verifyToken) {

        boolean ok = bindings.verify(
                bindId,
                verifyToken);

        if (!ok) {
            return ResponseEntity.status(HttpStatus.BAD_REQUEST)
                    .body(page(
                            "验证失败",
                            "链接无效或已过期，请回到 Agent Pager 重新绑定。"));
        }

        return ResponseEntity.ok(
                page(
                        "邮箱绑定成功",
                        "可以关闭本页面并返回 Agent Pager。"));
    }

    private static String realIp(
            HttpServletRequest request) {

        String forwarded =
                request.getHeader("X-Forwarded-For");

        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }

        return request.getRemoteAddr();
    }

    private static String page(
            String title,
            String text) {

        return """
                <!doctype html>
                <html lang="zh-CN">
                <head>
                  <meta charset="utf-8">
                  <meta name="viewport" content="width=device-width,initial-scale=1">
                  <title>Agent Pager</title>
                  <style>
                    body{font-family:system-ui,sans-serif;background:#f5f7fa;margin:0;padding:40px}
                    main{max-width:560px;margin:10vh auto;background:#fff;border:1px solid #e5e7eb;
                         border-radius:16px;padding:32px}
                    h2{margin-top:0} p{color:#667085;line-height:1.7}
                  </style>
                </head>
                <body><main><h2>%s</h2><p>%s</p></main></body>
                </html>
                """.formatted(title, text);
    }
}
