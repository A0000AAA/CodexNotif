package com.pravera.flutter_foreground_task

import android.content.Intent
import com.pravera.flutter_foreground_task.service.ForegroundService
import com.pravera.flutter_foreground_task.service.ForegroundServiceManager
import com.pravera.flutter_foreground_task.service.NotificationPermissionManager
import com.pravera.flutter_foreground_task.service.ServiceProvider
import com.pravera.flutter_foreground_task.service.AlertSoundPlayer
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry.NewIntentListener

/** FlutterForegroundTaskPlugin */
class FlutterForegroundTaskPlugin : FlutterPlugin, ActivityAware, ServiceProvider, NewIntentListener {
    companion object {
        private const val BACKGROUND_AUDIO_CHANNEL =
            "org.codexnotif.mobile/background_audio"

        fun addTaskLifecycleListener(listener: FlutterForegroundTaskLifecycleListener) {
            ForegroundService.addTaskLifecycleListener(listener)
        }

        fun removeTaskLifecycleListener(listener: FlutterForegroundTaskLifecycleListener) {
            ForegroundService.removeTaskLifecycleListener(listener)
        }
    }

    private lateinit var notificationPermissionManager: NotificationPermissionManager
    private lateinit var foregroundServiceManager: ForegroundServiceManager

    private var activityBinding: ActivityPluginBinding? = null
    private lateinit var methodCallHandler: MethodCallHandlerImpl
    private var backgroundAudioChannel: MethodChannel? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        notificationPermissionManager = NotificationPermissionManager()
        foregroundServiceManager = ForegroundServiceManager()

        methodCallHandler = MethodCallHandlerImpl(binding.applicationContext, this)
        methodCallHandler.init(binding.binaryMessenger)

        backgroundAudioChannel = MethodChannel(
            binding.binaryMessenger,
            BACKGROUND_AUDIO_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "startAlertSound" -> {
                            AlertSoundPlayer.start(
                                binding.applicationContext,
                                call.argument<String>("uri"),
                            )
                            result.success(null)
                        }

                        "stopAlertSound" -> {
                            AlertSoundPlayer.stop()
                            result.success(null)
                        }

                        else -> result.notImplemented()
                    }
                } catch (error: Exception) {
                    result.error(
                        "playback_failed",
                        "Unable to play the selected or bundled alert sound",
                        error.message,
                    )
                }
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        if (::methodCallHandler.isInitialized) {
            methodCallHandler.dispose()
        }
        backgroundAudioChannel?.setMethodCallHandler(null)
        backgroundAudioChannel = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        methodCallHandler.setActivity(binding.activity)
        binding.addRequestPermissionsResultListener(notificationPermissionManager)
        binding.addActivityResultListener(methodCallHandler)
        binding.addOnNewIntentListener(this)
        activityBinding = binding

        val intent = binding.activity.intent
        ForegroundService.handleNotificationContentIntent(intent)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        onDetachedFromActivity()
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        onAttachedToActivity(binding)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(notificationPermissionManager)
        activityBinding?.removeActivityResultListener(methodCallHandler)
        activityBinding?.removeOnNewIntentListener(this)
        activityBinding = null
        methodCallHandler.setActivity(null)
    }

    override fun onNewIntent(intent: Intent): Boolean {
        ForegroundService.handleNotificationContentIntent(intent)
        return true
    }

    override fun getNotificationPermissionManager() = notificationPermissionManager

    override fun getForegroundServiceManager() = foregroundServiceManager
}
