package org.codexnotif.server.controller;

import org.codexnotif.server.model.AuthCheckResponse;
import org.codexnotif.server.service.DeviceService;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
class AuthControllerTest {

    @Test
    void validDeviceTokenReportsBothAuthenticationLayers() {
        StubDeviceService devices = new StubDeviceService(true);
        AuthController controller = new AuthController(devices);

        AuthCheckResponse response = controller.check(
                "D_TEST", "Bearer device-token");

        assertTrue(response.accessKeyAuthenticated());
        assertTrue(response.deviceAuthenticated());
        assertEquals("D_TEST", devices.deviceId);
        assertEquals("device-token", devices.deviceToken);
    }

    @Test
    void invalidOrMissingDeviceTokenDoesNotRevealDeviceDetails() {
        StubDeviceService devices = new StubDeviceService(false);
        AuthController controller = new AuthController(devices);

        AuthCheckResponse response = controller.check("D_TEST", null);

        assertTrue(response.accessKeyAuthenticated());
        assertFalse(response.deviceAuthenticated());
        assertEquals(
                Arrays.asList(
                        "accessKeyAuthenticated",
                        "deviceAuthenticated"),
                Arrays.stream(AuthCheckResponse.class.getRecordComponents())
                        .map(component -> component.getName())
                        .toList());
    }

    private static final class StubDeviceService extends DeviceService {
        private final boolean validationResult;
        private String deviceId;
        private String deviceToken;

        private StubDeviceService(boolean validationResult) {
            super(null);
            this.validationResult = validationResult;
        }

        @Override
        public boolean validate(String deviceId, String rawToken) {
            this.deviceId = deviceId;
            this.deviceToken = rawToken;
            return validationResult;
        }
    }
}
