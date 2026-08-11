package org.codexnotif.server.controller;

import org.codexnotif.server.model.AuthCheckResponse;
import org.codexnotif.server.service.DeviceService;
import org.junit.jupiter.api.Test;

import java.util.Arrays;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

class AuthControllerTest {

    @Test
    void validDeviceTokenReportsBothAuthenticationLayers() {
        DeviceService devices = mock(DeviceService.class);
        when(devices.validate("D_TEST", "device-token")).thenReturn(true);
        AuthController controller = new AuthController(devices);

        AuthCheckResponse response = controller.check(
                "D_TEST", "Bearer device-token");

        assertTrue(response.accessKeyAuthenticated());
        assertTrue(response.deviceAuthenticated());
        verify(devices).validate("D_TEST", "device-token");
    }

    @Test
    void invalidOrMissingDeviceTokenDoesNotRevealDeviceDetails() {
        DeviceService devices = mock(DeviceService.class);
        when(devices.validate("D_TEST", null)).thenReturn(false);
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
}
