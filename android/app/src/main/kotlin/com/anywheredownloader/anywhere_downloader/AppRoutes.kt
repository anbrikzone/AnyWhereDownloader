package com.anywheredownloader.anywhere_downloader

import android.app.PendingIntent
import android.content.Context
import android.content.Intent

/**
 * Where a notification tap lands inside the app: the Downloads screen for a
 * download still in progress, the Library tab for one already saved. The
 * route travels as an extra on a [MainActivity] intent; MainActivity hands
 * it to Dart on the `anywhere_downloader/app_route` channel (drained once
 * on a cold start, pushed via onNewIntent while running) and `MainShell`
 * navigates.
 */
object AppRoutes {
    const val EXTRA_ROUTE = "awd_route"
    const val DOWNLOADS = "downloads"
    const val LIBRARY = "library"

    /** A tap target opening the app at [route]. Each route gets its own
     *  request code so the two PendingIntents don't overwrite each other's
     *  extras. */
    fun pendingIntent(context: Context, route: String): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            putExtra(EXTRA_ROUTE, route)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context,
            if (route == LIBRARY) 4101 else 4100,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun from(intent: Intent?): String? =
        intent?.getStringExtra(EXTRA_ROUTE)?.takeIf { it == DOWNLOADS || it == LIBRARY }
}
