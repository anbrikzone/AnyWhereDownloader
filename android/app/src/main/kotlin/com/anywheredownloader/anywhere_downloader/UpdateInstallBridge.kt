package com.anywheredownloader.anywhere_downloader

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Hands a downloaded release APK to the system package installer, and
 * reports/opens the "install unknown apps" per-source grant.
 *
 * Same shape as [MediaNotificationBridge]: a plain `ACTION_VIEW`
 * `Intent` fired at the OS, every call wrapped so a failure surfaces as a
 * `MethodChannel` error rather than crashing the app.
 */
class UpdateInstallBridge(private val appContext: Context) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getSupportedAbis" -> result.success(Build.SUPPORTED_ABIS.toList())

            "canInstallPackages" -> {
                result.success(appContext.packageManager.canRequestPackageInstalls())
            }

            "openInstallPermissionSettings" -> {
                try {
                    val intent = Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:${appContext.packageName}"),
                    ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    appContext.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("open_settings_failed", e.message, null)
                }
            }

            "openUrl" -> {
                val url = call.argument<String>("url")
                if (url == null) {
                    result.error("bad_args", "Missing 'url' argument", null)
                    return
                }
                try {
                    val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    appContext.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("open_url_failed", e.message, null)
                }
            }

            "installApk" -> {
                val path = call.argument<String>("path")
                if (path == null) {
                    result.error("bad_args", "Missing 'path' argument", null)
                    return
                }
                try {
                    val file = File(path)
                    val uri = FileProvider.getUriForFile(
                        appContext,
                        "${appContext.packageName}.fileprovider",
                        file,
                    )
                    val intent = Intent(Intent.ACTION_VIEW).apply {
                        setDataAndType(uri, "application/vnd.android.package-archive")
                        addFlags(
                            Intent.FLAG_ACTIVITY_NEW_TASK or
                                Intent.FLAG_GRANT_READ_URI_PERMISSION,
                        )
                    }
                    appContext.startActivity(intent)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install_failed", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }
}
