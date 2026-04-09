package com.example.bulk_sms

import android.app.IntentService
import android.content.Intent

/**
 * Stub service for RESPOND_VIA_MESSAGE.
 * Required to be eligible as the default messaging app.
 */
class HeadlessSmsSendService : IntentService("HeadlessSmsSendService") {

    @Deprecated("Deprecated in API 30, but we must extend IntentService for this role")
    override fun onHandleIntent(intent: Intent?) {
        // intentionally empty
    }
}
