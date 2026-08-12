package com.pravera.flutter_foreground_task.service

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

internal object XiaomiAlertActivityLauncher {
    const val EXTRA_STRONG_ALERT_PAYLOAD =
        "org.codexnotif.mobile.extra.STRONG_ALERT_PAYLOAD"
    private const val TAG = "CodexNotifAlert"

    fun isSupportedManufacturer(manufacturer: String): Boolean {
        val normalized = manufacturer.trim().lowercase()
        return normalized == "xiaomi" || normalized == "redmi" || normalized == "poco"
    }

    fun launch(context: Context, payload: String?): Boolean {
        if (!isSupportedManufacturer(Build.MANUFACTURER) || payload.isNullOrBlank()) {
            return false
        }
        val intent = context.packageManager
            .getLaunchIntentForPackage(context.packageName)
            ?: return false
        intent.addFlags(
            Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP,
        )
        intent.putExtra(EXTRA_STRONG_ALERT_PAYLOAD, payload)
        return try {
            context.startActivity(intent)
            true
        } catch (error: RuntimeException) {
            Log.w(TAG, "System rejected the best-effort alert activity launch")
            false
        }
    }
}
