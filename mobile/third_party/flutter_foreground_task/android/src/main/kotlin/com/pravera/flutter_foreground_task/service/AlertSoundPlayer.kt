package com.pravera.flutter_foreground_task.service

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.net.Uri
import android.util.Log
import java.io.IOException

internal object AlertSoundPlayer {
    private const val TAG = "CodexNotifAudio"
    private const val FALLBACK_SOUND = "tone_phone"

    private var player: MediaPlayer? = null

    @Synchronized
    @Throws(IOException::class)
    fun start(context: Context, requestedUri: String?) {
        stopLocked()

        val appContext = context.applicationContext
        val fallbackUri =
            "android.resource://${appContext.packageName}/raw/$FALLBACK_SOUND"
        val candidates = listOf(requestedUri, fallbackUri)
            .filterNotNull()
            .filter(String::isNotBlank)
            .distinct()

        var lastError: Exception? = null
        for (candidate in candidates) {
            try {
                val nextPlayer = createPlayer(appContext, candidate)
                nextPlayer.start()
                player = nextPlayer
                Log.i(TAG, "Background alarm playback started; looping=true")
                return
            } catch (error: Exception) {
                lastError = error
                Log.w(TAG, "Alarm source could not be opened: ${error.javaClass.simpleName}")
            }
        }

        throw IOException("Unable to play selected or bundled alert sound", lastError)
    }

    @Synchronized
    fun stop() {
        stopLocked()
    }

    private fun createPlayer(context: Context, uriText: String): MediaPlayer {
        val audioAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        val bundledName = AlertSoundUriResolver.bundledResourceName(
            uriText,
            context.packageName,
        )
        val nextPlayer = MediaPlayer()

        try {
            nextPlayer.setAudioAttributes(audioAttributes)
            if (bundledName != null) {
                val resourceId = context.resources.getIdentifier(
                    bundledName,
                    "raw",
                    context.packageName,
                )
                if (resourceId == 0) {
                    throw IOException("Bundled sound not found: $bundledName")
                }

                context.resources.openRawResourceFd(resourceId).use { descriptor ->
                    nextPlayer.setDataSource(
                        descriptor.fileDescriptor,
                        descriptor.startOffset,
                        descriptor.length,
                    )
                }
            } else {
                val uri = Uri.parse(uriText)
                if (uri.scheme == "android.resource") {
                    throw IOException("Invalid bundled sound URI: $uriText")
                }
                nextPlayer.setDataSource(context, uri)
            }

            nextPlayer.isLooping = true
            nextPlayer.prepare()
            return nextPlayer
        } catch (error: Exception) {
            nextPlayer.release()
            throw error
        }
    }

    private fun stopLocked() {
        val current = player ?: return
        player = null
        try {
            current.stop()
        } catch (_: IllegalStateException) {
        }
        current.release()
        Log.i(TAG, "Background alarm playback stopped")
    }
}
