package com.pravera.flutter_foreground_task.service

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class AlertSoundUriResolverTest {
    @Test
    fun `local raw resource is accepted`() {
        assertEquals(
            "tone_hajimi",
            AlertSoundUriResolver.bundledResourceName(
                "android.resource://org.codexnotif.mobile/raw/tone_hajimi",
                "org.codexnotif.mobile",
            ),
        )
    }

    @Test
    fun `resource from another package is rejected`() {
        assertNull(
            AlertSoundUriResolver.bundledResourceName(
                "android.resource://another.app/raw/tone_phone",
                "org.codexnotif.mobile",
            ),
        )
    }

    @Test
    fun `content uri is handled as an external source`() {
        assertNull(
            AlertSoundUriResolver.bundledResourceName(
                "content://media/external/audio/media/42",
                "org.codexnotif.mobile",
            ),
        )
    }

    @Test
    fun `malformed raw resource path is rejected`() {
        assertNull(
            AlertSoundUriResolver.bundledResourceName(
                "android.resource://org.codexnotif.mobile/drawable/tone_phone",
                "org.codexnotif.mobile",
            ),
        )
    }
}
