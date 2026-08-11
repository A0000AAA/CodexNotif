package com.pravera.flutter_foreground_task.service

import java.net.URI

internal object AlertSoundUriResolver {
    private val rawResourceName = Regex("^[a-z0-9_]+$")

    fun bundledResourceName(uriText: String?, packageName: String): String? {
        if (uriText.isNullOrBlank()) return null

        return try {
            val uri = URI(uriText)
            if (uri.scheme != "android.resource" || uri.host != packageName) {
                return null
            }

            val segments = uri.path
                ?.split('/')
                ?.filter(String::isNotEmpty)
                ?: return null
            if (segments.size != 2 || segments[0] != "raw") return null

            segments[1].takeIf(rawResourceName::matches)
        } catch (_: RuntimeException) {
            null
        }
    }
}
