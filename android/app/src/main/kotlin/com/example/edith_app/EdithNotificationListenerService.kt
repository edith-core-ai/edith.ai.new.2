package com.example.edith_app

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class EdithNotificationListenerService : NotificationListenerService() {

    companion object {
        var instance: EdithNotificationListenerService? = null
        private val recent = mutableListOf<Map<String, String>>()

        fun getRecent(limit: Int): List<Map<String, String>> {
            synchronized(recent) {
                return recent.takeLast(limit)
            }
        }
    }

    override fun onListenerConnected() {
        instance = this
    }

    override fun onListenerDisconnected() {
        instance = null
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        val extras = sbn.notification?.extras ?: return
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val pkg = sbn.packageName ?: ""
        val entry = mapOf(
            "package" to pkg,
            "title" to title,
            "text" to text,
            "time" to sbn.postTime.toString()
        )
        synchronized(recent) {
            recent.add(entry)
            if (recent.size > 50) recent.removeAt(0)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {}
}