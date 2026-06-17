package com.example.bulk_sms

import org.json.JSONArray
import org.json.JSONObject

data class BulkSmsRecipient(
    val number: String,
    val displayName: String? = null,
    val mergeTags: Map<String, String> = emptyMap(),
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("number", number)
        put("displayName", displayName)
        put("mergeTags", JSONObject(mergeTags))
    }

    companion object {
        fun fromJson(obj: JSONObject): BulkSmsRecipient {
            val tags = mutableMapOf<String, String>()
            val rawTags = obj.optJSONObject("mergeTags")
            if (rawTags != null) {
                rawTags.keys().forEachRemaining { key ->
                    tags[key] = rawTags.optString(key, "")
                }
            }
            return BulkSmsRecipient(
                number = obj.optString("number"),
                displayName = obj.optString("displayName").takeIf { it.isNotBlank() },
                mergeTags = tags,
            )
        }
    }
}

data class BulkSmsRecord(
    val number: String,
    val messageBody: String,
    val status: String,
    val sentAt: Long,
    val errorMessage: String? = null,
) {
    fun toJson(): JSONObject = JSONObject().apply {
        put("number", number)
        put("messageBody", messageBody)
        put("status", status)
        put("sentAt", sentAt)
        put("errorMessage", errorMessage)
    }

    companion object {
        fun fromJson(obj: JSONObject): BulkSmsRecord = BulkSmsRecord(
            number = obj.optString("number"),
            messageBody = obj.optString("messageBody"),
            status = obj.optString("status", "failed"),
            sentAt = obj.optLong("sentAt", System.currentTimeMillis()),
            errorMessage = obj.optString("errorMessage").takeIf { it.isNotBlank() },
        )
    }
}

data class BulkSmsJob(
    val jobId: String,
    val message: String,
    val recipients: List<BulkSmsRecipient>,
    val subscriptionId: Int?,
    val groupName: String?,
    val delayMs: Int,
    val batchSize: Int,
    var status: String = "queued",
    var sent: Int = 0,
    var failed: Int = 0,
    var nextIndex: Int = 0,
    val createdAt: Long = System.currentTimeMillis(),
    val records: MutableList<BulkSmsRecord> = mutableListOf(),
) {
    val total: Int get() = recipients.size

    fun toJson(includeRecords: Boolean = true): JSONObject = JSONObject().apply {
        put("jobId", jobId)
        put("message", message)
        put("recipients", JSONArray(recipients.map { it.toJson() }))
        put("subscriptionId", subscriptionId)
        put("groupName", groupName)
        put("delayMs", delayMs)
        put("batchSize", batchSize)
        put("status", status)
        put("sent", sent)
        put("failed", failed)
        put("nextIndex", nextIndex)
        put("createdAt", createdAt)
        if (includeRecords) {
            put("records", JSONArray(records.map { it.toJson() }))
        }
    }

    companion object {
        fun fromJson(obj: JSONObject, includeRecords: Boolean = true): BulkSmsJob {
            val recipients = mutableListOf<BulkSmsRecipient>()
            val rawRecipients = obj.optJSONArray("recipients") ?: JSONArray()
            for (i in 0 until rawRecipients.length()) {
                recipients += BulkSmsRecipient.fromJson(rawRecipients.getJSONObject(i))
            }

            val records = mutableListOf<BulkSmsRecord>()
            if (includeRecords) {
                val rawRecords = obj.optJSONArray("records") ?: JSONArray()
                for (i in 0 until rawRecords.length()) {
                    records += BulkSmsRecord.fromJson(rawRecords.getJSONObject(i))
                }
            }

            return BulkSmsJob(
                jobId = obj.optString("jobId"),
                message = obj.optString("message"),
                recipients = recipients,
                subscriptionId = if (obj.isNull("subscriptionId")) null else obj.optInt("subscriptionId"),
                groupName = obj.optString("groupName").takeIf { it.isNotBlank() },
                delayMs = obj.optInt("delayMs", 0),
                batchSize = obj.optInt("batchSize", 50),
                status = obj.optString("status", "queued"),
                sent = obj.optInt("sent", 0),
                failed = obj.optInt("failed", 0),
                nextIndex = obj.optInt("nextIndex", 0),
                createdAt = obj.optLong("createdAt", System.currentTimeMillis()),
                records = records,
            )
        }
    }
}

fun bulkSmsJobToMap(job: BulkSmsJob, recordsFrom: Int = 0): Map<String, Any?> = mapOf(
    "jobId" to job.jobId,
    "message" to job.message,
    "numbers" to job.recipients.map { it.number },
    "groupName" to job.groupName,
    "delayMs" to job.delayMs,
    "batchSize" to job.batchSize,
    "status" to job.status,
    "sent" to job.sent,
    "failed" to job.failed,
    "nextIndex" to job.nextIndex,
    "total" to job.total,
    "createdAt" to job.createdAt,
    "records" to job.records.drop(recordsFrom.coerceAtLeast(0)).map { record ->
        mapOf(
            "number" to record.number,
            "messageBody" to record.messageBody,
            "status" to record.status,
            "sentAt" to record.sentAt,
            "errorMessage" to record.errorMessage,
        )
    },
)
