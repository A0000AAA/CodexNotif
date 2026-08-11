package org.codexnotif.server.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;
import org.codexnotif.server.config.AppProperties;
import org.codexnotif.server.entity.DeviceEntity;
import org.codexnotif.server.model.EmailMessage;
import org.codexnotif.server.model.EventRequest;

import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

@Service
public class NotificationService {

    private static final Logger log =
            LoggerFactory.getLogger(NotificationService.class);

    private static final DateTimeFormatter TIME_FORMAT =
            DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss")
                    .withZone(ZoneId.systemDefault());

    private final AppProperties properties;
    private final EmailDispatchService email;

    public NotificationService(
            AppProperties properties,
            EmailDispatchService email) {
        this.properties = properties;
        this.email = email;
    }

    public void notify(DeviceEntity device, EventRequest event) {
        if ("log".equalsIgnoreCase(properties.getNotificationMode())) {
            log.info(
                    "NOTIFY device={} email={} source={} event={} time={}",
                    event.deviceId(),
                    maskEmail(device.getEmail()),
                    event.source(),
                    event.event(),
                    event.timestamp());
            return;
        }

        String title = "agent.completed".equals(event.event())
                ? "Codex 任务已完成"
                : "CodexNotif 通知";

        String subject =
                properties.getEmail().getSubjectPrefix()
                        + " "
                        + title;

        String text = title
                + "\n\n设备：" + event.deviceId()
                + "\n来源：" + event.source()
                + "\n事件：" + event.event()
                + "\n时间：" + TIME_FORMAT.format(event.timestamp().toInstant())
                + "\n\n请回到电脑查看结果。"
                + "\n\nCodexNotif";

        email.send(new EmailMessage(
                device.getEmail(),
                subject,
                text));
    }

    private static String maskEmail(String value) {
        if (value == null || value.isBlank()) return "(none)";

        int at = value.indexOf('@');

        if (at <= 1) return "***";

        return value.substring(0, 1)
                + "***"
                + value.substring(at);
    }
}
