package com.anywheredownloader.anywhere_downloader

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.atomic.AtomicInteger

/**
 * Posts the final "download complete" notification for a saved file —
 * separate from [YtDlpDownloadService]'s own in-progress notification.
 * The completion notification's tap action is a plain `ACTION_VIEW`
 * `PendingIntent` pointing directly at the saved MediaStore item, so
 * opening the file works even if the app process has since been killed —
 * no round-trip back into Dart is needed on tap.
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
                DownloadNotifications.showDownloadComplete(appContext, title, text, uri, mimeType)
                result.success(null)
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
    private val nextRequestCode = AtomicInteger(3000)

    fun showDownloadComplete(
        context: Context,
        title: String,
        text: String,
        uri: String?,
        mimeType: String?,
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

        ensureChannel(context)

        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setAutoCancel(true)

        if (uri != null && mimeType != null) {
            val viewIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(Uri.parse(uri), mimeType)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            val pendingIntent = PendingIntent.getActivity(
                context,
                nextRequestCode.getAndIncrement(),
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.setContentIntent(pendingIntent)
        }

        try {
            NotificationManagerCompat.from(context)
                .notify(nextNotificationId.getAndIncrement(), builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS was revoked between the check above and
            // this call — never let a notification failure surface as a
            // download failure.
        }
    }

    private fun ensureChannel(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL_ID, "Downloads complete", NotificationManager.IMPORTANCE_DEFAULT)
        )
    }
}
