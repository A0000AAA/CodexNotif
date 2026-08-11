package org.codexnotif.server.controller;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.codexnotif.server.config.AppProperties;
import org.codexnotif.server.model.EmailMessage;
import org.codexnotif.server.security.TokenUtil;
import org.codexnotif.server.service.EmailDispatchService;
import org.codexnotif.server.service.MicrosoftOAuthService;

import java.net.URI;

@RestController
@RequestMapping("/admin")
public class MicrosoftAdminController {

    private final AppProperties properties;
    private final MicrosoftOAuthService microsoft;
    private final EmailDispatchService email;

    public MicrosoftAdminController(
            AppProperties properties,
            MicrosoftOAuthService microsoft,
            EmailDispatchService email) {
        this.properties = properties;
        this.microsoft = microsoft;
        this.email = email;
    }

    @GetMapping("/microsoft/connect")
    public ResponseEntity<Void> connect(
            @RequestParam String setupToken) {

        requireAdmin(setupToken);

        return ResponseEntity.status(HttpStatus.FOUND)
                .location(URI.create(
                        microsoft.createAuthorizationUrl()))
                .build();
    }

    @GetMapping(
            value = "/microsoft/callback",
            produces = "text/html;charset=UTF-8")
    public ResponseEntity<String> callback(
            @RequestParam String code,
            @RequestParam String state) {

        microsoft.acceptCallback(code, state);

        return ResponseEntity.ok("""
                <!doctype html>
                <meta charset="utf-8">
                <title>CodexNotif</title>
                <h2>Microsoft 邮箱连接成功</h2>
                <p>Refresh Token 已加密保存到本地 H2 数据库，可以关闭本页面。</p>
                """);
    }

    @PostMapping("/test-email")
    public ResponseEntity<?> testEmail(
            @RequestParam String setupToken,
            @RequestParam String to) {

        requireAdmin(setupToken);

        email.send(new EmailMessage(
                to,
                properties.getEmail().getSubjectPrefix()
                        + " 测试邮件",
                "CodexNotif 邮件通道测试成功。"));

        return ResponseEntity.ok(
                java.util.Map.of(
                        "ok", true,
                        "message", "Test email accepted."));
    }

    private void requireAdmin(String token) {
        String expected =
                properties.getAdminSetupToken();

        if (expected == null
                || expected.isBlank()
                || !TokenUtil.constantTimeEquals(
                        expected,
                        token)) {
            throw new AdminUnauthorizedException();
        }
    }

    @ResponseStatus(HttpStatus.UNAUTHORIZED)
    private static class AdminUnauthorizedException
            extends RuntimeException {
    }
}
