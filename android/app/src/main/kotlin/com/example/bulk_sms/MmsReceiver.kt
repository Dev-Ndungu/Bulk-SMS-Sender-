package com.example.bulk_sms

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Stub receiver for WAP_PUSH_DELIVER (MMS).
 * Required to be eligible as the default messaging app.
 */
class MmsReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context?, intent: Intent?) {
        // intentionally empty
    }
}
