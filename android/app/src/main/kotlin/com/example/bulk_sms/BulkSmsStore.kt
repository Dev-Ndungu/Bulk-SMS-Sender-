package com.example.bulk_sms

import android.content.Context
import org.json.JSONObject

object BulkSmsStore {
    private const val PREFS = "bulk_sms_store"
    private const val JOB_KEY_PREFIX = "job_"

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveJob(context: Context, job: BulkSmsJob) {
        prefs(context).edit().putString(JOB_KEY_PREFIX + job.jobId, job.toJson().toString()).apply()
    }

    fun getJob(context: Context, jobId: String): BulkSmsJob? {
        val raw = prefs(context).getString(JOB_KEY_PREFIX + jobId, null) ?: return null
        return runCatching { BulkSmsJob.fromJson(JSONObject(raw)) }.getOrNull()
    }

    fun getJobs(context: Context): List<BulkSmsJob> {
        val all = mutableListOf<BulkSmsJob>()
        val rawPrefs = prefs(context).all
        for ((key, value) in rawPrefs) {
            if (!key.startsWith(JOB_KEY_PREFIX)) continue
            val raw = value as? String ?: continue
            runCatching { BulkSmsJob.fromJson(JSONObject(raw)) }
                .getOrNull()
                ?.let { all += it }
        }
        return all.sortedByDescending { it.createdAt }
    }

    fun cancelJob(context: Context, jobId: String) {
        val job = getJob(context, jobId) ?: return
        job.status = "cancelled"
        saveJob(context, job)
    }

    fun clearJob(context: Context, jobId: String) {
        prefs(context).edit().remove(JOB_KEY_PREFIX + jobId).apply()
    }
}
