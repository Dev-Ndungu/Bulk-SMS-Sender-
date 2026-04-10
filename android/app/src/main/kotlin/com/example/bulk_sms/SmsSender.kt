package com.example.bulk_sms

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager

object SmsSender {
    @Suppress("DEPRECATION")
    fun sendSms(context: Context, number: String, message: String, subscriptionId: Int?) {
        val smsManager: SmsManager = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val base = context.getSystemService(SmsManager::class.java)
                    ?: throw IllegalStateException("SmsManager not available")
                if (subscriptionId != null && subscriptionId >= 0) {
                    base.createForSubscriptionId(subscriptionId)
                } else {
                    base
                }
            } else if (subscriptionId != null && subscriptionId >= 0
                && Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                @Suppress("DEPRECATION")
                SmsManager.getSmsManagerForSubscriptionId(subscriptionId)
            } else {
                @Suppress("DEPRECATION")
                SmsManager.getDefault()
            }
        } catch (_: Exception) {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        val parts = smsManager.divideMessage(message)
        if (parts.size <= 1) {
            smsManager.sendTextMessage(number, null, message, null, null)
        } else {
            smsManager.sendMultipartTextMessage(number, null, parts, null, null)
        }

        writeSentSms(context, number, message)
    }

    private fun writeSentSms(context: Context, number: String, body: String) {
        try {
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, number)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.SEEN, 1)
            }
            context.contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
        } catch (_: Exception) {
            // Best effort — may fail if not default SMS app.
        }
    }
}
