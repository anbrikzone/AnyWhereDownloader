package com.anywheredownloader.anywhere_downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * Posts the final "download complete" notification for a saved file —
 * separate from [YtDlpDownloadService]'s own in-progress notification.
 * Tapping the completion notification opens the app on its Library tab
 * ([AppRoutes]). The Downloads screen's "open" uses [handle]'s `openFile`,
 * a plain `ACTION_VIEW` of the saved MediaStore item.
 */
class MediaNotificationBridge(private val appContext: Context) {
    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "showDownloadComplete" -> {
                val title = call.argument<String>("title")
                if (title == null) {
                    result.error("bad_args", "Missing 'title' argument", null)
                    return
                }
                val text = call.argument<String>("text") ?: "Tap to open"
                val uri = call.argument<String>("uri")
                val mimeType = call.argument<String>("mimeType")
                val channelName = call.argument<String>("channelName")
                DownloadNotifications.showDownloadComplete(
                    appContext,
                    title,
                    text,
                    uri,
                    mimeType,
                    channelName,
                )
                result.success(null)
            }

            // The Downloads screen's "tap to open" — the same ACTION_VIEW the
            // completion notification fires. Returns false when no installed
            // app can show it (or the item is gone).
            "openFile" -> {
                val uri = call.argument<String>("uri")
                if (uri == null) {
                    result.error("bad_args", "Missing 'uri' argument", null)
                    return
                }
                val parsed = Uri.parse(uri)
                val mimeType = call.argument<String>("mimeType")
                    ?: appContext.contentResolver.getType(parsed)
                val intent = Intent(Intent.ACTION_VIEW).apply {
                    setDataAndType(parsed, mimeType)
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
                }
                result.success(
                    try {
                        appContext.startActivity(intent)
                        true
                    } catch (e: Exception) {
                        Log.w("MediaNotificationBridge", "openFile($uri) failed", e)
                        false
                    },
                )
            }

            else -> result.notImplemented()
        }
    }
}

/**
 * The notification itself, callable without a MethodChannel —
 * [YtDlpDownloadService] posts it directly once it has saved a file, so it
 * still appears when the Flutter UI is gone.
 */
object DownloadNotifications {
    private const val CHANNEL_ID = "download_complete"
    private val nextNotificationId = AtomicInteger(2000)

    fun showDownloadComplete(
        context: Context,
        title: String,
        text: String,
        uri: String?,
        mimeType: String?,
        // Localized system-settings name of the channel; applied on every
        // post so a language change renames it too.
        channelName: String? = null,
    ) {
        // POST_NOTIFICATIONS only exists from API 33 — checking it on 31/32
        // would always report "denied".
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ActivityCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }

        ensureChannel(context, channelName ?: "Downloads complete")

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setAutoCancel(true)

        // Tap → the app's Library tab (user request 2026-10-03) — for a
        // single saved file and for a summary alike. The Downloads screen's
        // "open" still hands a file to an external viewer.
        builder.setContentIntent(AppRoutes.pendingIntent(context, AppRoutes.LIBRARY))

        try {
            NotificationManagerCompat.from(context)
                .notify(nextNotificationId.getAndIncrement(), builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS was revoked between the check above and
            // this call — never let a notification failure surface as a
            // download failure.
        }
    }

    private fun ensureChannel(context: Context, name: String) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, name, NotificationManager.IMPORTANCE_DEFAULT)
        )
    }
}
