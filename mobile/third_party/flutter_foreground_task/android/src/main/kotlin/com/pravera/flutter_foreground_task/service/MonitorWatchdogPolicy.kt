package com.pravera.flutter_foreground_task.service

enum class MonitorWatchdogDecision {
    HEALTHY,
    WAITING,
    RECOVER,
    STALE,
}

object MonitorWatchdogPolicy {
    const val NO_PROGRESS_RECOVERY_AFTER_MILLIS = 45_000L
    const val STALE_AFTER_MILLIS = 90_000L
    const val RECOVERY_COOLDOWN_MILLIS = 60_000L

    fun decide(
        nowMillis: Long,
        progressMarker: String,
        lastObservedProgressMarker: String,
        lastProgressAtMillis: Long,
        lastRecoveryAtMillis: Long,
    ): MonitorWatchdogDecision {
        if (progressMarker.isNotEmpty() && progressMarker != lastObservedProgressMarker) {
            return MonitorWatchdogDecision.HEALTHY
        }

        val noProgressMillis = nowMillis - lastProgressAtMillis
        val recoveryCooldownElapsed = lastRecoveryAtMillis == 0L ||
                nowMillis - lastRecoveryAtMillis >= RECOVERY_COOLDOWN_MILLIS

        if (lastRecoveryAtMillis != 0L &&
            nowMillis - lastRecoveryAtMillis >= NO_PROGRESS_RECOVERY_AFTER_MILLIS &&
            !recoveryCooldownElapsed) {
            return MonitorWatchdogDecision.STALE
        }

        if (noProgressMillis >= NO_PROGRESS_RECOVERY_AFTER_MILLIS && recoveryCooldownElapsed) {
            return MonitorWatchdogDecision.RECOVER
        }

        if (noProgressMillis > STALE_AFTER_MILLIS) {
            return MonitorWatchdogDecision.STALE
        }

        return MonitorWatchdogDecision.WAITING
    }
}
