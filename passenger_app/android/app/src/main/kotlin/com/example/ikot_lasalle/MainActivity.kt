package com.example.ikot_lasalle

import android.media.AudioAttributes
import android.media.Ringtone
import android.media.RingtoneManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val alertHandler = Handler(Looper.getMainLooper())
    private var alertRingtone: Ringtone? = null
    private val stopAlert = Runnable { stopAlertSound() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "ikot_lasalle/ride_alert")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        try {
                            stopAlertSound()
                            val alarm = call.argument<String>("kind") == "alarm"
                            val type = if (alarm) RingtoneManager.TYPE_ALARM
                                else RingtoneManager.TYPE_NOTIFICATION
                            val uri = RingtoneManager.getActualDefaultRingtoneUri(this, type)
                            if (uri != null) {
                                alertRingtone = RingtoneManager.getRingtone(this, uri)
                                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                                    val usage = if (alarm) AudioAttributes.USAGE_ALARM
                                        else AudioAttributes.USAGE_NOTIFICATION_EVENT
                                    alertRingtone?.audioAttributes = AudioAttributes.Builder()
                                        .setUsage(usage)
                                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                                        .build()
                                }
                                if (alarm && Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                    alertRingtone?.setLooping(true)
                                }
                                alertRingtone?.play()
                                if (alarm) alertHandler.postDelayed(stopAlert, 10000)
                            }
                            result.success(null)
                        } catch (error: Exception) {
                            stopAlertSound()
                            result.error("ALERT_SOUND", error.message, null)
                        }
                    }
                    "stop" -> {
                        stopAlertSound()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun stopAlertSound() {
        alertHandler.removeCallbacks(stopAlert)
        alertRingtone?.stop()
        alertRingtone = null
    }

    override fun onDestroy() {
        stopAlertSound()
        super.onDestroy()
    }
}
