package se.cstate.ytdlp_flutter

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * Android backend: wraps youtubedl-android (bundled Python + runtime-updatable
 * yt-dlp + FFmpeg). All engine calls run on a thread pool; results and
 * progress events are posted back on the main thread.
 */
class YtdlpFlutterPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var progressChannel: EventChannel
    private lateinit var context: Context

    private val executor: ExecutorService = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var progressSink: EventChannel.EventSink? = null

    @Volatile
    private var initialized = false

    @Volatile
    private var lastUpdateStatus: String = "not-attempted"

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "ytdlp_flutter")
        channel.setMethodCallHandler(this)
        progressChannel = EventChannel(binding.binaryMessenger, "ytdlp_flutter/progress")
        progressChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                progressSink = events
            }

            override fun onCancel(arguments: Any?) {
                progressSink = null
            }
        })
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        progressChannel.setStreamHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "init" -> runAsync(result) {
                ensureInit()
                null
            }
            "getVideoInfo" -> {
                val url = call.argument<String>("url")
                    ?: return result.error("BAD_ARGS", "url is required", null)
                runAsync(result) {
                    ensureInit()
                    val request = YoutubeDLRequest(url).apply {
                        addOption("--dump-single-json")
                        addOption("--no-playlist")
                    }
                    YoutubeDL.getInstance().execute(request).out.trim()
                }
            }
            "downloadAudio" -> {
                val url = call.argument<String>("url")
                    ?: return result.error("BAD_ARGS", "url is required", null)
                val outputDir = call.argument<String>("outputDir")
                    ?: return result.error("BAD_ARGS", "outputDir is required", null)
                val taskId = call.argument<String>("taskId")
                    ?: return result.error("BAD_ARGS", "taskId is required", null)
                val format = call.argument<String>("format") ?: "bestaudio/best"
                val audioFormat = call.argument<String>("audioFormat")
                runAsync(result) {
                    ensureInit()
                    downloadAudio(url, outputDir, taskId, format, audioFormat)
                }
            }
            "cancel" -> {
                val taskId = call.argument<String>("taskId")
                    ?: return result.error("BAD_ARGS", "taskId is required", null)
                result.success(YoutubeDL.getInstance().destroyProcessById(taskId))
            }
            "update" -> runAsync(result) {
                ensureInit()
                val status = YoutubeDL.getInstance()
                    .updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
                status?.name ?: "unknown"
            }
            else -> result.notImplemented()
        }
    }

    @Synchronized
    private fun ensureInit() {
        if (initialized) return
        YoutubeDL.getInstance().init(context)
        FFmpeg.getInstance().init(context)
        // The library's bundled yt-dlp is frozen at its build date, and a
        // stale extractor is the #1 failure mode (YouTube 403s it within
        // months). Update in place — a no-op when already current, and
        // never fatal: offline devices proceed with the installed version.
        try {
            val status = YoutubeDL.getInstance()
                .updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
            lastUpdateStatus = status?.name ?: "unknown"
            Log.i("ytdlp_flutter", "yt-dlp update: $lastUpdateStatus")
        } catch (e: Exception) {
            lastUpdateStatus = "failed: ${e.message}"
            Log.w("ytdlp_flutter", "yt-dlp update failed (continuing): ${e.message}")
        }
        initialized = true
    }

    /// Version + update status, appended to every error so failures on
    /// user devices are self-describing.
    private fun engineInfo(): String {
        val version = try {
            YoutubeDL.getInstance().version(context) ?: "unknown"
        } catch (e: Exception) {
            "unknown"
        } catch (e: LinkageError) {
            "unknown"
        }
        return "yt-dlp=$version, update=$lastUpdateStatus"
    }

    private fun downloadAudio(
        url: String,
        outputDir: String,
        taskId: String,
        format: String,
        audioFormat: String?,
    ): String {
        File(outputDir).mkdirs()
        val request = YoutubeDLRequest(url).apply {
            addOption("--no-playlist")
            addOption("-f", format)
            if (audioFormat != null) {
                addOption("-x")
                addOption("--audio-format", audioFormat)
            }
            addOption("-o", "$outputDir/%(id)s.%(ext)s")
            addOption("--no-simulate")
            addOption("--print", "after_move:filepath")
        }
        val response = YoutubeDL.getInstance().execute(request, taskId) { progress, eta, _ ->
            mainHandler.post {
                progressSink?.success(
                    mapOf(
                        "taskId" to taskId,
                        "progress" to progress,
                        "etaSeconds" to eta,
                    )
                )
            }
        }
        // '--print after_move:filepath' emits the finished file on stdout;
        // scan from the end past any progress noise.
        val path = response.out.lines()
            .map { it.trim() }
            .lastOrNull { it.startsWith("/") && File(it).exists() }
            ?: throw RuntimeException("yt-dlp finished but printed no file path")
        return path
    }

    private fun runAsync(result: Result, block: () -> Any?) {
        executor.execute {
            try {
                val value = block()
                mainHandler.post { result.success(value) }
            } catch (e: YoutubeDL.CanceledException) {
                mainHandler.post { result.error("CANCELLED", "cancelled", null) }
            } catch (e: Exception) {
                reportFailure(result, e)
            } catch (e: LinkageError) {
                // Some youtubedl-android initialization failures are JVM
                // Errors (not Exceptions). Letting one escape this worker
                // thread terminates the whole Android process, preventing
                // Dart from falling back to its direct stream source.
                reportFailure(result, e)
            }
        }
    }

    private fun reportFailure(result: Result, error: Throwable) {
        Log.e("ytdlp_flutter", "yt-dlp operation failed", error)
        val message = error.cause?.message ?: error.message
            ?: error.javaClass.simpleName
        mainHandler.post {
            result.error("YTDLP_ERROR", message, engineInfo())
        }
    }
}
