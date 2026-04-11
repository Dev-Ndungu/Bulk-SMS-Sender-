package com.example.bulk_sms

import android.content.Context
import android.util.Log
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit

object BulkSmsJobRunner {
    private val executor = Executors.newSingleThreadExecutor()
    private val runningJobs = ConcurrentHashMap<String, Future<*>>()

    fun resumePendingJobs(context: Context) {
        BulkSmsStore.getJobs(context)
            .filter { it.status == "queued" || it.status == "running" || it.status == "paused" }
            .forEach { start(context, it.jobId) }
    }

    fun start(context: Context, jobId: String) {
        if (runningJobs.containsKey(jobId)) return

        val future = executor.submit {
            runJob(context.applicationContext, jobId)
        }
        runningJobs[jobId] = future
    }

    fun cancel(context: Context, jobId: String) {
        BulkSmsStore.cancelJob(context, jobId)
        runningJobs.remove(jobId)?.cancel(true)
    }

    private fun runJob(context: Context, jobId: String) {
        try {
            val job = BulkSmsStore.getJob(context, jobId) ?: return
            if (job.status == "cancelled" || job.status == "completed") return

            job.status = "running"
            BulkSmsStore.saveJob(context, job)

            for (index in job.nextIndex until job.recipients.size) {
                if (Thread.currentThread().isInterrupted) {
                    job.status = "paused"
                    BulkSmsStore.saveJob(context, job)
                    return
                }

                val recipient = job.recipients[index]
                val body = applyMergeTags(job.message, recipient)

                var ok = false
                var errorMessage: String? = null
                try {
                    SmsSender.sendSms(
                        context = context,
                        number = recipient.number,
                        message = body,
                        subscriptionId = job.subscriptionId,
                    )
                    ok = true
                } catch (e: Exception) {
                    errorMessage = e.message ?: "SMS send failed"
                    Log.e("BulkSmsJobRunner", "Failed to send SMS to ${recipient.number}", e)
                }

                job.records += BulkSmsRecord(
                    number = recipient.number,
                    messageBody = body,
                    status = if (ok) "sent" else "failed",
                    sentAt = System.currentTimeMillis(),
                    errorMessage = errorMessage,
                )
                if (ok) {
                    job.sent += 1
                } else {
                    job.failed += 1
                }
                job.nextIndex = index + 1
                BulkSmsStore.saveJob(context, job)

                if (job.delayMs > 0) {
                    TimeUnit.MILLISECONDS.sleep(job.delayMs.toLong())
                }
                if (job.batchSize > 0 && job.nextIndex < job.recipients.size &&
                    job.nextIndex % job.batchSize == 0
                ) {
                    TimeUnit.MILLISECONDS.sleep(500)
                }
            }

            job.status = "completed"
            BulkSmsStore.saveJob(context, job)
        } catch (e: Exception) {
            val job = BulkSmsStore.getJob(context, jobId)
            if (job != null && job.status != "cancelled") {
                job.status = "failed"
                BulkSmsStore.saveJob(context, job)
            }
        } finally {
            runningJobs.remove(jobId)
        }
    }

    private fun applyMergeTags(message: String, recipient: BulkSmsRecipient): String {
        var body = message
        recipient.mergeTags.forEach { (key, value) ->
            body = body.replace("{{$key}}", value)
        }
        recipient.displayName?.let { name ->
            body = body.replace("{{name}}", name)
        }
        body = body.replace("{{phone}}", recipient.number)
        return body
    }
}
