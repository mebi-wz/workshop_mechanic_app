package com.hagbes.workshop_mechanic

import android.os.SystemClock
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val CHANNEL = "com.hagbes.workshop_mechanic/anti_tamper"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAutoTimeEnabled" -> {
                    try {
                        val autoTime = Settings.Global.getInt(contentResolver, Settings.Global.AUTO_TIME, 0) == 1
                        val autoTimeZone = Settings.Global.getInt(contentResolver, Settings.Global.AUTO_TIME_ZONE, 0) == 1
                        result.success(autoTime && autoTimeZone)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "getElapsedRealtime" -> {
                    result.success(SystemClock.elapsedRealtime())
                }
                else -> result.notImplemented()
            }
        }
    }
}


