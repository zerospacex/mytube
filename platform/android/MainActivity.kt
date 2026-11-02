package com.custom.ytadfree.adfree_youtube

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var askedNotifications = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mytube/background")
        BackgroundPlaybackService.onCommand = { action, position ->
            channel?.invokeMethod("mediaCommand", mapOf("action" to action, "position" to position))
        }
        channel?.setMethodCallHandler { call, result ->
            try {
                val intent = Intent(this, BackgroundPlaybackService::class.java)
                when (call.method) {
                    "setEnabled" -> {
                        val enabled = call.arguments == true
                        if (enabled || BackgroundPlaybackService.isRunning) {
                            intent.putExtra("background", enabled)
                            startPlaybackService(intent)
                        }
                    }
                    "updateMedia" -> {
                        val state = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                        if (state["hasMedia"] != true) {
                            stopService(intent)
                        } else if (state["playing"] == true || BackgroundPlaybackService.isRunning) {
                            intent.putExtra("background", state["background"] == true)
                            intent.putExtra("title", state["trackTitle"] as? String ?: "MyTube Music")
                            intent.putExtra("artist", state["artist"] as? String ?: "")
                            intent.putExtra("playing", state["playing"] == true)
                            intent.putExtra("duration", (state["duration"] as? Number)?.toLong() ?: 0L)
                            intent.putExtra("position", (state["position"] as? Number)?.toLong() ?: 0L)
                            startPlaybackService(intent)
                        }
                    }
                    "clearMedia" -> stopService(intent)
                    else -> {
                        result.notImplemented()
                        return@setMethodCallHandler
                    }
                }
                result.success(null)
            } catch (error: Exception) {
                result.error("media_controls_failed", error.message, null)
            }
        }
    }

    private fun startPlaybackService(intent: Intent) {
        if (!askedNotifications && Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            askedNotifications = true
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 42)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) startForegroundService(intent)
        else startService(intent)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        BackgroundPlaybackService.onCommand = null
        channel?.setMethodCallHandler(null)
        channel = null
        stopService(Intent(this, BackgroundPlaybackService::class.java))
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
