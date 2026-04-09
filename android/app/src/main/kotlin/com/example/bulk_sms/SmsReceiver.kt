package com.example.bulk_sms

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Telephony
import androidx.core.app.NotificationCompat

/**
 * Receives incoming SMS when we are the default SMS app.
 * - Writes messages to content://sms/inbox so other apps can see them
 * - Posts an Android notification
 * - Forwards to Flutter via a static callback
 */
class SmsReceiver : BroadcastReceiver() {

    companion object {
        var onSmsReceived: ((sender: String, body: String, timestamp: Long) -> Unit)? = null
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (intent == null || context == null) return
        val messages = Telephony.Sms.Intents.getMessagesFromIntent(intent)

        for (msg in messages) {
            val sender = msg.displayOriginatingAddress ?: continue
            val body = msg.displayMessageBody ?: ""
            val ts = msg.timestampMillis

            // 1) Write to system SMS database so other apps see it
            writeReceivedSms(context, sender, body, ts)

            // 2) Show notification
            showNotification(context, sender, body)

            // 3) Forward to Flutter (if running)
            onSmsReceived?.invoke(sender, body, ts)
        }
    }

    private fun writeReceivedSms(
        context: Context, sender: String, body: String, timestamp: Long
    ) {
        try {
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, sender)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, timestamp)
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_INBOX)
                put(Telephony.Sms.READ, 0)
                put(Telephony.Sms.SEEN, 0)
            }
            context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
        } catch (_: Exception) {}
    }

    private fun showNotification(context: Context, sender: String, body: String) {
        try {
            val launchIntent = context.packageManager
                .getLaunchIntentForPackage(context.packageName)
            val pending = PendingIntent.getActivity(
                context, sender.hashCode(), launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M)
                            PendingIntent.FLAG_IMMUTABLE else 0
            )

            val notification = NotificationCompat.Builder(context, "sms_channel")
                .setSmallIcon(android.R.drawable.sym_action_email)
                .setContentTitle(sender)
                .setContentText(body)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .setAutoCancel(true)
                .setContentIntent(pending)
                .build()

            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                    as NotificationManager
            nm.notify(sender.hashCode(), notification)
        } catch (_: Exception) {}
    }
}
