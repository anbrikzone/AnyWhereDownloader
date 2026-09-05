package com.anywheredownloader.anywhere_downloader

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/**
 * Holds the active MethodChannel so components that aren't directly wired
 * into the Flutter plugin lifecycle (like [YtDlpDownloadService], a plain
 * Android Service) can still call back into Dart. Same process, so a
 * simple static holder is enough — no cross-process IPC involved.
 */
object NativeToDartChannel {
    @Volatile var channel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    fun invoke(method: String, arguments: Any?) {
        val ch = channel ?: return
        mainHandler.post { ch.invokeMethod(method, arguments) }
    }
}
