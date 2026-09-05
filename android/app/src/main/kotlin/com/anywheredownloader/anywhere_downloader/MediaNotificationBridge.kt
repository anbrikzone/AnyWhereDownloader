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
    companion object {
        private const val CHANNEL_ID = "download_complete"
        private val nextNotificationId = AtomicInteger(2000)
        private val nextRequestCode = AtomicInteger(3000)
    }

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
                showDownloadComplete(title, text, uri, mimeType)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun showDownloadComplete(title: String, text: String, uri: String?, mimeType: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = ActivityCompat.checkSelfPermission(
                appContext,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }

        ensureChannel()

        val builder = NotificationCompat.Builder(appContext, CHANNEL_ID)
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
                appContext,
                nextRequestCode.getAndIncrement(),
                viewIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            builder.setContentIntent(pendingIntent)
        }

        try {
            NotificationManagerCompat.from(appContext)
                .notify(nextNotificationId.getAndIncrement(), builder.build())
        } catch (e: SecurityException) {
            // POST_NOTIFICATIONS was revoked between the check above and
            // this call — never let a notification failure surface as a
            // download failure.
        }
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = appContext.getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL_ID, "Downloads complete", NotificationManager.IMPORTANCE_DEFAULT)
            )
        }
    }
}
