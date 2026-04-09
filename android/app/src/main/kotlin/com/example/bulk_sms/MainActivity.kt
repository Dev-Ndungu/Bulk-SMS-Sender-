package com.example.bulk_sms

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.role.RoleManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Telephony
import android.telephony.SmsManager
import android.telephony.SubscriptionManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.bulk_sms/sms"
    private val EVENT_CHANNEL = "com.example.bulk_sms/incoming_sms"
    private val REQUEST_DEFAULT_SMS = 1001
    private var pendingResult: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createNotificationChannel()

        // ── EventChannel: stream incoming SMS to Dart ──────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    SmsReceiver.onSmsReceived = { sender, body, timestamp ->
                        events?.success(mapOf(
                            "sender" to sender,
                            "body" to body,
                            "timestamp" to timestamp
                        ))
                    }
                }
                override fun onCancel(arguments: Any?) {
                    SmsReceiver.onSmsReceived = null
                }
            })

        // ── MethodChannel ──────────────────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getSimCards" -> {
                        try { result.success(getSimCards()) }
                        catch (e: Exception) { result.error("SIM_ERROR", e.message, null) }
                    }
                    "sendSms" -> {
                        try {
                            val number = call.argument<String>("number")
                                ?: return@setMethodCallHandler result.error(
                                    "INVALID_ARG", "number is required", null)
                            val message = call.argument<String>("message")
                                ?: return@setMethodCallHandler result.error(
                                    "INVALID_ARG", "message is required", null)
                            val subId = call.argument<Int>("subscriptionId")
                            sendSms(number, message, subId)
                            // Write to system content provider so other apps see it
                            writeSentSms(number, message)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_ERROR", e.message, e.stackTraceToString())
                        }
                    }
                    "isDefaultSmsApp" -> result.success(isDefaultSmsApp())
                    "requestDefaultSmsApp" -> {
                        pendingResult = result
                        requestDefaultSmsRole()
                    }
                    "getConversations" -> {
                        try { result.success(getConversations()) }
                        catch (e: Exception) { result.error("READ_ERROR", e.message, null) }
                    }
                    "getMessagesForNumber" -> {
                        try {
                            val number = call.argument<String>("number")
                                ?: return@setMethodCallHandler result.error(
                                    "INVALID_ARG", "number is required", null)
                            result.success(getMessagesForNumber(number))
                        } catch (e: Exception) { result.error("READ_ERROR", e.message, null) }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ── Notification channel ────────────────────────────────────────────
    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                "sms_channel", "Incoming SMS",
                NotificationManager.IMPORTANCE_HIGH
            ).apply { description = "Notifications for incoming SMS" }
            val nm = getSystemService(NotificationManager::class.java)
            nm?.createNotificationChannel(ch)
        }
    }

    // ── Default SMS app ─────────────────────────────────────────────────
    private fun isDefaultSmsApp(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            Telephony.Sms.getDefaultSmsPackage(this) == packageName
        } else false
    }

    private fun requestDefaultSmsRole() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val rm = getSystemService(RoleManager::class.java)
            if (rm != null && rm.isRoleAvailable(RoleManager.ROLE_SMS)
                && !rm.isRoleHeld(RoleManager.ROLE_SMS)) {
                startActivityForResult(
                    rm.createRequestRoleIntent(RoleManager.ROLE_SMS),
                    REQUEST_DEFAULT_SMS)
                return
            }
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            val intent = Intent(Telephony.Sms.Intents.ACTION_CHANGE_DEFAULT)
            intent.putExtra(Telephony.Sms.Intents.EXTRA_PACKAGE_NAME, packageName)
            startActivityForResult(intent, REQUEST_DEFAULT_SMS)
            return
        }
        pendingResult?.success(isDefaultSmsApp())
        pendingResult = null
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_DEFAULT_SMS) {
            pendingResult?.success(isDefaultSmsApp())
            pendingResult = null
        }
    }

    // ── Write sent SMS to system content provider ───────────────────────
    private fun writeSentSms(number: String, body: String) {
        try {
            val values = ContentValues().apply {
                put(Telephony.Sms.ADDRESS, number)
                put(Telephony.Sms.BODY, body)
                put(Telephony.Sms.DATE, System.currentTimeMillis())
                put(Telephony.Sms.TYPE, Telephony.Sms.MESSAGE_TYPE_SENT)
                put(Telephony.Sms.READ, 1)
                put(Telephony.Sms.SEEN, 1)
            }
            contentResolver.insert(Telephony.Sms.CONTENT_URI, values)
        } catch (_: Exception) {
            // Best effort — may fail if not default SMS app
        }
    }

    // ── Read conversations from system ──────────────────────────────────
    private fun getConversations(): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        val seen = mutableSetOf<String>()
        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE
            ),
            null, null,
            "${Telephony.Sms.DATE} DESC"
        )
        cursor?.use {
            while (it.moveToNext()) {
                val addr = it.getString(0) ?: continue
                val canonical = addr.replace(Regex("[^+0-9]"), "")
                if (canonical.isEmpty() || !seen.add(canonical)) continue
                results.add(mapOf(
                    "number" to canonical,
                    "body" to (it.getString(1) ?: ""),
                    "timestamp" to it.getLong(2),
                    "type" to it.getInt(3)  // 1=inbox, 2=sent
                ))
                if (results.size >= 200) break  // cap for performance
            }
        }
        return results
    }

    // ── Read messages for a specific number ─────────────────────────────
    private fun getMessagesForNumber(number: String): List<Map<String, Any?>> {
        val results = mutableListOf<Map<String, Any?>>()
        // Match both the raw number and common variants
        val clean = number.replace(Regex("[^+0-9]"), "")
        val selection = "${Telephony.Sms.ADDRESS} LIKE ?"
        // Match last 9 digits to handle +254 vs 0 prefix differences
        val matchSuffix = if (clean.length >= 9) clean.takeLast(9) else clean
        val selArgs = arrayOf("%$matchSuffix")

        val cursor = contentResolver.query(
            Telephony.Sms.CONTENT_URI,
            arrayOf(
                Telephony.Sms.ADDRESS,
                Telephony.Sms.BODY,
                Telephony.Sms.DATE,
                Telephony.Sms.TYPE
            ),
            selection, selArgs,
            "${Telephony.Sms.DATE} ASC"
        )
        cursor?.use {
            while (it.moveToNext()) {
                results.add(mapOf(
                    "number" to (it.getString(0) ?: number),
                    "body" to (it.getString(1) ?: ""),
                    "timestamp" to it.getLong(2),
                    "type" to it.getInt(3)
                ))
            }
        }
        return results
    }

    private fun getSimCards(): List<Map<String, Any>> {
        val simList = mutableListOf<Map<String, Any>>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            if (checkSelfPermission(android.Manifest.permission.READ_PHONE_STATE)
                == PackageManager.PERMISSION_GRANTED
            ) {
                val sm = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                        as? SubscriptionManager
                sm?.activeSubscriptionInfoList?.forEach { sub ->
                    simList.add(
                        mapOf(
                            "subscriptionId" to sub.subscriptionId,
                            "displayName"    to (sub.displayName?.toString()
                                ?: "SIM ${sub.simSlotIndex + 1}"),
                            "carrierName"    to (sub.carrierName?.toString() ?: ""),
                            "slotIndex"      to sub.simSlotIndex,
                            "number"         to (sub.number ?: ""),
                        )
                    )
                }
            }
        }

        // Always provide at least one entry so the UI has something to show
        if (simList.isEmpty()) {
            simList.add(
                mapOf(
                    "subscriptionId" to -1,
                    "displayName"    to "Default SIM",
                    "carrierName"    to "",
                    "slotIndex"      to 0,
                    "number"         to "",
                )
            )
        }
        return simList
    }

    @Suppress("DEPRECATION")
    private fun sendSms(number: String, message: String, subscriptionId: Int?) {
        val smsManager: SmsManager = try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // API 31+: service-based, then create for subscription if needed
                val base = applicationContext.getSystemService(SmsManager::class.java)
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
        } catch (e: Exception) {
            @Suppress("DEPRECATION")
            SmsManager.getDefault()
        }

        // Always use divideMessage to handle both single and multipart properly
        val parts: ArrayList<String> = smsManager.divideMessage(message)
        if (parts.size <= 1) {
            smsManager.sendTextMessage(number, null, message, null, null)
        } else {
            smsManager.sendMultipartTextMessage(number, null, parts, null, null)
        }
    }
}

