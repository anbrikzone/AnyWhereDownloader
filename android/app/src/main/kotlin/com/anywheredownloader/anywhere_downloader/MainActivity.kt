package com.anywheredownloader.anywhere_downloader

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "anywhere_downloader/yt_dlp"
    private val notificationsChannelName = "anywhere_downloader/media_notifications"
    private val updateInstallChannelName = "anywhere_downloader/update_install"
    private val mediaSaveChannelName = "anywhere_downloader/media_save"
    private val shareChannelName = "anywhere_downloader/share_intent"

    // Text the app was cold-started with via ACTION_SEND, held until Dart
    // pulls it once through `getInitialSharedText`. A share that arrives
    // while the app is already running goes straight to Dart from
    // onNewIntent instead (see below).
    private var initialSharedText: String? = null
    private var shareChannel: MethodChannel? = null

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

        val mediaSaveBridge = MediaSaveBridge(applicationContext)
        val mediaSaveChannel =
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, mediaSaveChannelName)
        mediaSaveChannel.setMethodCallHandler { call, result ->
            mediaSaveBridge.handle(call, result)
        }

        // Share-sheet entry point. `getInitialSharedText` is a one-shot
        // drain of a cold-start share; `sharedText` is pushed native -> Dart
        // for a share received while running.
        val shareCh = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, shareChannelName)
        shareCh.setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialSharedText" -> {
                    result.success(initialSharedText)
                    initialSharedText = null
                }
                else -> result.notImplemented()
            }
        }
        shareChannel = shareCh
        // The intent that started this activity — may be an ACTION_SEND.
        initialSharedText = extractSharedText(intent)

        // Init + self-update the bundled yt-dlp off the critical path, so a
        // fresh binary is usually in place before the user pastes a link.
        YtDlpCore.warmUp(applicationContext)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // Keep getIntent() current for anything that reads it later.
        setIntent(intent)
        val text = extractSharedText(intent) ?: return
        val ch = shareChannel
        if (ch != null) {
            ch.invokeMethod("sharedText", text)
        } else {
            // Engine not wired yet — fall back to the cold-start path.
            initialSharedText = text
        }
    }

    /** Pulls the shared text out of an ACTION_SEND text/plain intent. */
    private fun extractSharedText(intent: Intent?): String? {
        if (intent == null || intent.action != Intent.ACTION_SEND) return null
        if (intent.type != "text/plain") return null
        val text = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        return if (text.isNullOrEmpty()) null else text
    }
}
