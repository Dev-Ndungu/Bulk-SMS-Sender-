package com.example.bulk_sms

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object BulkSmsStore {
    private const val PREFS = "bulk_sms_store"
    private const val JOB_KEY_PREFIX = "job_"
    private const val PROGRESS_KEY_PREFIX = "progress_"
    private const val RECORD_COUNT_KEY_PREFIX = "record_count_"
    private const val RECORD_CHUNK_KEY_PREFIX = "records_"
    private const val RECORD_CHUNK_SIZE = 200

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveJob(context: Context, job: BulkSmsJob) {
        val store = prefs(context)
        val editor = store.edit()
        val jobKey = JOB_KEY_PREFIX + job.jobId

        if (!store.contains(jobKey)) {
            editor.putString(jobKey, job.toJson(includeRecords = false).toString())
        }
        editor.putString(progressKey(job.jobId), progressJson(job).toString())
        editor.apply()
    }

    fun appendRecord(context: Context, jobId: String, record: BulkSmsRecord) {
        val store = prefs(context)
        val currentCount = store.getInt(RECORD_COUNT_KEY_PREFIX + jobId, 0)
        val chunkIndex = currentCount / RECORD_CHUNK_SIZE
        val key = recordChunkKey(jobId, chunkIndex)
        val existing = store.getString(key, null)
        val chunk = if (existing == null) {
            JSONArray()
        } else {
            runCatching { JSONArray(existing) }.getOrDefault(JSONArray())
        }

        chunk.put(record.toJson())
        store.edit()
            .putString(key, chunk.toString())
            .putInt(RECORD_COUNT_KEY_PREFIX + jobId, currentCount + 1)
            .apply()
    }

    fun getJob(
        context: Context,
        jobId: String,
        includeRecords: Boolean = true,
        recordsFrom: Int = 0,
    ): BulkSmsJob? {
        val store = prefs(context)
        val raw = store.getString(JOB_KEY_PREFIX + jobId, null) ?: return null
        val job = runCatching {
            BulkSmsJob.fromJson(JSONObject(raw), includeRecords = false)
        }.getOrNull()
            ?: return null

        val hasProgress = applyProgress(store.getString(progressKey(jobId), null), job)
        if (!hasProgress) {
            applyRecordCountProgress(store, jobId, job)
        }

        if (includeRecords) {
            val chunkedRecords = readRecords(context, jobId, recordsFrom)
            if (chunkedRecords.isNotEmpty() || hasRecordChunks(context, jobId)) {
                job.records.clear()
                job.records.addAll(chunkedRecords)
                if (!hasProgress) {
                    applyRecordStatusCounts(job)
                }
            } else if (job.records.isNotEmpty()) {
                migrateLegacyRecords(context, job)
                if (recordsFrom > 0) {
                    val legacyRecords = job.records.drop(recordsFrom)
                    job.records.clear()
                    job.records.addAll(legacyRecords)
                }
            }
        } else {
            job.records.clear()
        }

        return job
    }

    fun getJobs(context: Context, includeRecords: Boolean = true): List<BulkSmsJob> {
        val all = mutableListOf<BulkSmsJob>()
        val rawPrefs = prefs(context).all
        for ((key, value) in rawPrefs) {
            if (!key.startsWith(JOB_KEY_PREFIX)) continue
            val jobId = key.removePrefix(JOB_KEY_PREFIX)
            val raw = value as? String ?: continue
            val job = runCatching {
                BulkSmsJob.fromJson(JSONObject(raw), includeRecords = false)
            }.getOrNull()
                ?: continue

            val hasProgress = applyProgress(
                prefs(context).getString(progressKey(jobId), null),
                job
            )
            if (!hasProgress) {
                applyRecordCountProgress(prefs(context), jobId, job)
            }
            if (includeRecords) {
                val chunkedRecords = readRecords(context, jobId)
                if (chunkedRecords.isNotEmpty() || hasRecordChunks(context, jobId)) {
                    job.records.clear()
                    job.records.addAll(chunkedRecords)
                    if (!hasProgress) {
                        applyRecordStatusCounts(job)
                    }
                } else if (job.records.isNotEmpty()) {
                    migrateLegacyRecords(context, job)
                }
            } else {
                job.records.clear()
            }
            all += job
        }
        return all.sortedByDescending { it.createdAt }
    }

    fun cancelJob(context: Context, jobId: String) {
        val job = getJob(context, jobId, includeRecords = false) ?: return
        job.status = "cancelled"
        saveJob(context, job)
    }

    fun clearJob(context: Context, jobId: String) {
        val store = prefs(context)
        val editor = store.edit()
            .remove(JOB_KEY_PREFIX + jobId)
            .remove(progressKey(jobId))
            .remove(RECORD_COUNT_KEY_PREFIX + jobId)

        val chunkPrefix = recordChunkPrefix(jobId)
        for (key in store.all.keys) {
            if (key.startsWith(chunkPrefix)) {
                editor.remove(key)
            }
        }
        editor.apply()
    }

    private fun progressJson(job: BulkSmsJob): JSONObject = JSONObject().apply {
        put("status", job.status)
        put("sent", job.sent)
        put("failed", job.failed)
        put("nextIndex", job.nextIndex)
    }

    private fun applyProgress(rawProgress: String?, job: BulkSmsJob): Boolean {
        if (rawProgress == null) return false
        return runCatching {
            val progress = JSONObject(rawProgress)
            job.status = progress.optString("status", job.status)
            job.sent = progress.optInt("sent", job.sent)
            job.failed = progress.optInt("failed", job.failed)
            job.nextIndex = progress.optInt("nextIndex", job.nextIndex)
        }.isSuccess
    }

    private fun applyRecordCountProgress(
        store: android.content.SharedPreferences,
        jobId: String,
        job: BulkSmsJob,
    ) {
        val recordCount = store.getInt(RECORD_COUNT_KEY_PREFIX + jobId, 0)
        if (recordCount <= 0) return
        val processed = recordCount.coerceAtMost(job.recipients.size)
        job.nextIndex = maxOf(job.nextIndex, processed)
        if (job.nextIndex >= job.recipients.size) {
            job.status = "completed"
        } else if (job.status == "queued") {
            job.status = "paused"
        }
    }

    private fun applyRecordStatusCounts(job: BulkSmsJob) {
        job.sent = job.records.count { it.status == "sent" || it.status == "delivered" }
        job.failed = job.records.count { it.status == "failed" }
    }

    private fun readRecords(
        context: Context,
        jobId: String,
        from: Int = 0,
    ): List<BulkSmsRecord> {
        val store = prefs(context)
        val total = store.getInt(RECORD_COUNT_KEY_PREFIX + jobId, 0)
        if (total <= 0 || from >= total) return emptyList()

        val records = mutableListOf<BulkSmsRecord>()
        val start = from.coerceAtLeast(0)
        val firstChunk = start / RECORD_CHUNK_SIZE
        val lastChunk = (total - 1) / RECORD_CHUNK_SIZE

        for (chunkIndex in firstChunk..lastChunk) {
            val rawChunk = store.getString(recordChunkKey(jobId, chunkIndex), null)
                ?: continue
            val chunk = runCatching { JSONArray(rawChunk) }.getOrNull() ?: continue
            val skipInChunk = if (chunkIndex == firstChunk) {
                start % RECORD_CHUNK_SIZE
            } else {
                0
            }

            for (index in skipInChunk until chunk.length()) {
                val obj = chunk.optJSONObject(index) ?: continue
                records += BulkSmsRecord.fromJson(obj)
            }
        }
        return records
    }

    private fun migrateLegacyRecords(context: Context, job: BulkSmsJob) {
        if (hasRecordChunks(context, job.jobId)) return
        for (record in job.records) {
            appendRecord(context, job.jobId, record)
        }
        prefs(context).edit()
            .putString(JOB_KEY_PREFIX + job.jobId, job.toJson(includeRecords = false).toString())
            .putString(progressKey(job.jobId), progressJson(job).toString())
            .apply()
    }

    private fun hasRecordChunks(context: Context, jobId: String): Boolean =
        prefs(context).contains(RECORD_COUNT_KEY_PREFIX + jobId)

    private fun progressKey(jobId: String): String = PROGRESS_KEY_PREFIX + jobId

    private fun recordChunkPrefix(jobId: String): String =
        RECORD_CHUNK_KEY_PREFIX + jobId + "_"

    private fun recordChunkKey(jobId: String, chunkIndex: Int): String =
        recordChunkPrefix(jobId) + chunkIndex
}
