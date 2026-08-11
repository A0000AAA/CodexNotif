package com.pravera.flutter_foreground_task.service

import kotlin.test.Test
import kotlin.test.assertEquals

class MonitorWatchdogPolicyTest {
    @Test
    fun `new heartbeat is healthy`() {
        val decision = MonitorWatchdogPolicy.decide(
            nowMillis = 100_000,
            progressMarker = "15:00:30",
            lastObservedProgressMarker = "15:00:00",
            lastProgressAtMillis = 60_000,
            lastRecoveryAtMillis = 0,
        )

        assertEquals(MonitorWatchdogDecision.HEALTHY, decision)
    }

    @Test
    fun `one pending scan interval does not restart task`() {
        val decision = MonitorWatchdogPolicy.decide(
            nowMillis = 104_999,
            progressMarker = "15:00:30",
            lastObservedProgressMarker = "15:00:30",
            lastProgressAtMillis = 60_000,
            lastRecoveryAtMillis = 0,
        )

        assertEquals(MonitorWatchdogDecision.WAITING, decision)
    }

    @Test
    fun `missing progress for forty five seconds rebuilds task`() {
        val decision = MonitorWatchdogPolicy.decide(
            nowMillis = 105_000,
            progressMarker = "15:00:30",
            lastObservedProgressMarker = "15:00:30",
            lastProgressAtMillis = 60_000,
            lastRecoveryAtMillis = 0,
        )

        assertEquals(MonitorWatchdogDecision.RECOVER, decision)
    }

    @Test
    fun `recovery cooldown prevents an engine restart loop`() {
        val decision = MonitorWatchdogPolicy.decide(
            nowMillis = 200_000,
            progressMarker = "15:00:30",
            lastObservedProgressMarker = "15:00:30",
            lastProgressAtMillis = 155_000,
            lastRecoveryAtMillis = 155_000,
        )

        assertEquals(MonitorWatchdogDecision.STALE, decision)
    }

    @Test
    fun `missing first heartbeat also rebuilds task`() {
        val decision = MonitorWatchdogPolicy.decide(
            nowMillis = 45_000,
            progressMarker = "",
            lastObservedProgressMarker = "",
            lastProgressAtMillis = 0,
            lastRecoveryAtMillis = 0,
        )

        assertEquals(MonitorWatchdogDecision.RECOVER, decision)
    }

    @Test
    fun `unchanged notification marker never reports healthy`() {
        val decision = MonitorWatchdogPolicy.decide(
            nowMillis = 130_000,
            progressMarker = "15:00:30",
            lastObservedProgressMarker = "15:00:30",
            lastProgressAtMillis = 60_000,
            lastRecoveryAtMillis = 100_000,
        )

        assertEquals(MonitorWatchdogDecision.WAITING, decision)
    }
}
