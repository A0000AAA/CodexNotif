package org.codexnotif.mobile;

import android.app.Activity;
import android.content.ContentResolver;
import android.content.ContentValues;
import android.content.Intent;
import android.content.res.AssetFileDescriptor;
import android.media.AudioAttributes;
import android.media.MediaPlayer;
import android.media.Ringtone;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import android.provider.MediaStore;
import android.util.Log;
import android.webkit.MimeTypeMap;

import androidx.annotation.NonNull;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.HashMap;
import java.util.Map;

public class MainActivity extends FlutterActivity {
    private static final String CHANNEL = "org.codexnotif.mobile/system_sound";
    private static final String ALERT_LAUNCH_CHANNEL =
            "org.codexnotif.mobile/alert_launch";
    private static final String EXTRA_STRONG_ALERT_PAYLOAD =
            "org.codexnotif.mobile.extra.STRONG_ALERT_PAYLOAD";
    private static final int PICK_RINGTONE_REQUEST = 7102;
    private static final String TAG = "CodexNotifAudio";

    private MethodChannel.Result pendingRingtoneResult;
    private MethodChannel alertLaunchChannel;
    private String pendingStrongAlertPayload;
    private MediaPlayer previewPlayer;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        alertLaunchChannel = new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                ALERT_LAUNCH_CHANNEL
        );
        alertLaunchChannel.setMethodCallHandler((call, result) -> {
            if (!"takePendingStrongAlert".equals(call.method)) {
                result.notImplemented();
                return;
            }
            final String payload = pendingStrongAlertPayload;
            pendingStrongAlertPayload = null;
            result.success(payload);
        });
        captureStrongAlertPayload(getIntent(), false);

        new MethodChannel(
                flutterEngine.getDartExecutor().getBinaryMessenger(),
                CHANNEL
        ).setMethodCallHandler((call, result) -> {
            if ("previewSound".equals(call.method)) {
                playPreviewSound(call.argument("uri"), result);
                return;
            }
            if ("stopPreviewSound".equals(call.method)) {
                stopPreviewPlayer();
                result.success(null);
                return;
            }
            if ("persistSound".equals(call.method)) {
                final String source = call.argument("uri");
                final String title = call.argument("title");
                if (source == null || source.isEmpty()) {
                    result.error("invalid_uri", "铃声地址为空", null);
                    return;
                }
                result.success(
                        persistPickedSound(
                                Uri.parse(source),
                                title == null || title.isEmpty() ? "手机本地声音" : title
                        ).toString()
                );
                return;
            }

            if (!"pickSound".equals(call.method)) {
                result.notImplemented();
                return;
            }

            if (pendingRingtoneResult != null) {
                result.error(
                        "already_active",
                        "系统铃声选择器已经打开",
                        null
                );
                return;
            }

            Intent intent = new Intent(RingtoneManager.ACTION_RINGTONE_PICKER);
            intent.addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION |
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
            );
            intent.putExtra(
                    RingtoneManager.EXTRA_RINGTONE_TYPE,
                    RingtoneManager.TYPE_ALL
            );
            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_DEFAULT, true);
            intent.putExtra(RingtoneManager.EXTRA_RINGTONE_SHOW_SILENT, false);

            final String existingUri = call.argument("existingUri");
            if (existingUri != null && !existingUri.isEmpty()) {
                intent.putExtra(
                        RingtoneManager.EXTRA_RINGTONE_EXISTING_URI,
                        Uri.parse(existingUri)
                );
            }

            final Intent xiaomiThemePicker = new Intent(intent)
                    .setPackage("com.android.thememanager");
            if (getPackageManager().resolveActivity(xiaomiThemePicker, 0) == null) {
                result.error(
                        "xiaomi_picker_unavailable",
                        "未找到小米主题铃声页面",
                        null
                );
                return;
            }
            intent = xiaomiThemePicker;

            pendingRingtoneResult = result;
            try {
                startActivityForResult(intent, PICK_RINGTONE_REQUEST);
            } catch (RuntimeException error) {
                pendingRingtoneResult = null;
                result.error(
                        "picker_unavailable",
                        "无法打开系统铃声选择器",
                        error.getMessage()
                );
            }
        });
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        setIntent(intent);
        captureStrongAlertPayload(intent, true);
    }

    private void captureStrongAlertPayload(Intent intent, boolean pushNow) {
        if (intent == null) return;
        final String payload = intent.getStringExtra(EXTRA_STRONG_ALERT_PAYLOAD);
        intent.removeExtra(EXTRA_STRONG_ALERT_PAYLOAD);
        if (payload == null || payload.isEmpty()) return;
        if (pushNow && alertLaunchChannel != null) {
            alertLaunchChannel.invokeMethod("showStrongAlert", payload);
        } else {
            pendingStrongAlertPayload = payload;
        }
    }

    private void playPreviewSound(
            String requestedUri,
            MethodChannel.Result result
    ) {
        stopPreviewPlayer();

        final String fallback =
                "android.resource://" + getPackageName() + "/raw/tone_phone";
        MediaPlayer player;
        try {
            player = createAlarmPlayer(
                    Uri.parse(
                            requestedUri == null || requestedUri.isEmpty()
                                    ? fallback
                                    : requestedUri
                    ),
                    false
            );
        } catch (IOException | RuntimeException firstError) {
            Log.w(TAG, "Selected ringtone could not be opened; using bundled tone", firstError);
            try {
                player = createAlarmPlayer(Uri.parse(fallback), false);
            } catch (IOException | RuntimeException fallbackError) {
                result.error(
                        "playback_failed",
                        "无法播放所选铃声或内置备用铃声",
                        fallbackError.getMessage()
                );
                return;
            }
        }

        player.setOnCompletionListener(completed -> {
            if (previewPlayer == completed) {
                previewPlayer = null;
            }
            completed.release();
        });
        previewPlayer = player;
        player.start();
        Log.i(TAG, "Preview playback started");
        result.success(null);
    }

    private MediaPlayer createAlarmPlayer(Uri uri, boolean looping)
            throws IOException {
        final AudioAttributes alarmAttributes = new AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_ALARM)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build();
        final String bundledName = BundledSoundResolver.resourceNameFor(
                uri.toString(),
                getPackageName()
        );

        if (bundledName != null) {
            final int resourceId = bundledSoundResourceId(bundledName);
            if (resourceId == 0) {
                throw new IOException("找不到内置铃声：" + bundledName);
            }

            final MediaPlayer bundledPlayer = openBundledAlarmPlayer(
                    resourceId,
                    alarmAttributes,
                    looping
            );
            if (bundledPlayer == null) {
                throw new IOException("无法打开内置铃声：" + bundledName);
            }

            Log.i(TAG, "Bundled alarm sound opened: " + bundledName);
            return bundledPlayer;
        }

        final MediaPlayer player = new MediaPlayer();
        try {
            player.setAudioAttributes(alarmAttributes);
            player.setDataSource(this, uri);
            player.setLooping(looping);
            player.prepare();
            return player;
        } catch (IOException | RuntimeException error) {
            player.release();
            throw error;
        }
    }

    private int bundledSoundResourceId(String bundledName) throws IOException {
        switch (bundledName) {
            case "tone_alert":
                return R.raw.tone_alert;
            case "tone_chime":
                return R.raw.tone_chime;
            case "tone_hajimi":
                return R.raw.tone_hajimi;
            case "tone_phone":
                return R.raw.tone_phone;
            case "tone_soft":
                return R.raw.tone_soft;
            default:
                throw new IOException("Unknown bundled sound: " + bundledName);
        }
    }

    private MediaPlayer openBundledAlarmPlayer(
            int resourceId,
            AudioAttributes alarmAttributes,
            boolean looping
    ) throws IOException {
        final MediaPlayer player = new MediaPlayer();
        try (AssetFileDescriptor descriptor =
                     getResources().openRawResourceFd(resourceId)) {
            if (descriptor == null) {
                throw new IOException("Bundled sound has no file descriptor");
            }
            player.setAudioAttributes(alarmAttributes);
            player.setDataSource(
                    descriptor.getFileDescriptor(),
                    descriptor.getStartOffset(),
                    descriptor.getLength()
            );
            player.setLooping(looping);
            player.prepare();
            return player;
        } catch (IOException | RuntimeException error) {
            player.release();
            throw error;
        }
    }

    private void stopPreviewPlayer() {
        if (previewPlayer == null) return;
        try {
            previewPlayer.stop();
        } catch (IllegalStateException ignored) {
        }
        previewPlayer.release();
        previewPlayer = null;
    }

    @Override
    protected void onDestroy() {
        stopPreviewPlayer();
        super.onDestroy();
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);

        if (requestCode != PICK_RINGTONE_REQUEST || pendingRingtoneResult == null) {
            return;
        }

        final MethodChannel.Result result = pendingRingtoneResult;
        pendingRingtoneResult = null;

        if (resultCode != Activity.RESULT_OK || data == null) {
            result.success(null);
            return;
        }

        final Uri uri = data.getParcelableExtra(
                RingtoneManager.EXTRA_RINGTONE_PICKED_URI
        );
        if (uri == null) {
            result.success(null);
            return;
        }

        String title = "手机本地声音";
        final Ringtone ringtone = RingtoneManager.getRingtone(this, uri);
        if (ringtone != null) {
            final String resolvedTitle = ringtone.getTitle(this);
            if (resolvedTitle != null && !resolvedTitle.isEmpty()) {
                title = resolvedTitle;
            }
        }

        final Uri persistentUri = persistPickedSound(uri, title);
        final Map<String, String> value = new HashMap<>();
        value.put("uri", persistentUri.toString());
        value.put("title", title);
        result.success(value);
    }

    private Uri persistPickedSound(Uri sourceUri, String title) {
        final String scheme = sourceUri.getScheme();
        final String authority = sourceUri.getAuthority();
        if (ContentResolver.SCHEME_ANDROID_RESOURCE.equals(scheme) ||
                "media".equals(authority) ||
                "settings".equals(authority) ||
                Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return sourceUri;
        }

        final ContentResolver resolver = getContentResolver();
        final String mimeType = resolver.getType(sourceUri) == null
                ? "audio/mpeg"
                : resolver.getType(sourceUri);
        String extension = MimeTypeMap.getSingleton()
                .getExtensionFromMimeType(mimeType);
        if (extension == null || extension.isEmpty()) {
            extension = "mp3";
        }

        final String safeTitle = title
                .replaceAll("[^A-Za-z0-9\\u4e00-\\u9fa5._-]", "_")
                .replaceAll("_+", "_");
        final ContentValues values = new ContentValues();
        values.put(
                MediaStore.Audio.Media.DISPLAY_NAME,
                "codexnotif_" + safeTitle + "_" + System.currentTimeMillis() + "." + extension
        );
        values.put(MediaStore.Audio.Media.MIME_TYPE, mimeType);
        values.put(
                MediaStore.Audio.Media.RELATIVE_PATH,
                "Ringtones/CodexNotif"
        );
        values.put(MediaStore.Audio.Media.IS_RINGTONE, 1);
        values.put(MediaStore.Audio.Media.IS_NOTIFICATION, 1);
        values.put(MediaStore.Audio.Media.IS_ALARM, 1);
        values.put(MediaStore.Audio.Media.IS_PENDING, 1);

        Uri targetUri = null;
        try {
            targetUri = resolver.insert(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    values
            );
            if (targetUri == null) {
                return sourceUri;
            }

            try (
                    InputStream input = resolver.openInputStream(sourceUri);
                    OutputStream output = resolver.openOutputStream(targetUri, "w")
            ) {
                if (input == null || output == null) {
                    throw new IOException("无法打开所选铃声");
                }
                final byte[] buffer = new byte[16 * 1024];
                int count;
                while ((count = input.read(buffer)) != -1) {
                    output.write(buffer, 0, count);
                }
            }

            final ContentValues ready = new ContentValues();
            ready.put(MediaStore.Audio.Media.IS_PENDING, 0);
            resolver.update(targetUri, ready, null, null);
            return targetUri;
        } catch (IOException | RuntimeException error) {
            if (targetUri != null) {
                resolver.delete(targetUri, null, null);
            }
            return sourceUri;
        }
    }
}
