package com.pravera.flutter_foreground_task.service

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class XiaomiAlertActivityLauncherTest {
    @Test
    fun recognizesXiaomiFamilyOnly() {
        assertTrue(XiaomiAlertActivityLauncher.isSupportedManufacturer("Xiaomi"))
        assertTrue(XiaomiAlertActivityLauncher.isSupportedManufacturer("REDMI"))
        assertTrue(XiaomiAlertActivityLauncher.isSupportedManufacturer(" poco "))
        assertFalse(XiaomiAlertActivityLauncher.isSupportedManufacturer("Google"))
        assertFalse(XiaomiAlertActivityLauncher.isSupportedManufacturer("Samsung"))
    }
}
