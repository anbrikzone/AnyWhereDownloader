package com.anywheredownloader.anywhere_downloader

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "anywhere_downloader/yt_dlp"
    private val notificationsChannelName = "anywhere_downloader/media_notifications"
    private val updateInstallChannelName = "anywhere_downloader/update_install"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val bridge = YtDlpBridge(applicationContext)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
        channel.setMethodCallHandler { call, result -> bridge.handle(call, result) }
        NativeToDartChannel.channel = channel

        val notificationBridge = MediaNotificationBridge(applicationContext)
        val notificationsChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, notificationsChannelName)
        notificationsChannel.setMethodCallHandler { call, result ->
            notificationBridge.handle(call, result)
        }

        val updateInstallBridge = UpdateInstallBridge(applicationContext)
        val updateInstallChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, updateInstallChannelName)
        updateInstallChannel.setMethodCallHandler { call, result ->
            updateInstallBridge.handle(call, result)
        }
    }
}
