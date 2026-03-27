package com.example.volume_controller

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.EventChannel
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.volume_controller/service"
    private val EVENT_CHANNEL = "com.example.volume_controller/events"
    
    private var eventSink: EventChannel.EventSink? = null
    private var volumeReceiver: BroadcastReceiver? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startService" -> {
                    val intent = Intent(this, VolumeControllerService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopService" -> {
                    val intent = Intent(this, VolumeControllerService::class.java)
                    stopService(intent)
                    result.success(null)
                }
                "isAccessibilityEnabled" -> {
                    val enabledServices = Settings.Secure.getString(contentResolver, Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES)
                    val isEnabled = enabledServices?.contains(packageName + "/.VolumeControllerService") == true
                    result.success(isEnabled)
                }
                "requestAccessibility" -> {
                    val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                    startActivity(intent)
                    result.success(null)
                }
                "hasWriteSettingsPermission" -> {
                    val hasPerm = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        Settings.System.canWrite(this)
                    } else {
                        true
                    }
                    result.success(hasPerm)
                }
                "requestWriteSettingsPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        val intent = Intent(Settings.ACTION_MANAGE_WRITE_SETTINGS)
                        intent.data = Uri.parse("package:" + this.packageName)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    volumeReceiver = object : BroadcastReceiver() {
                        override fun onReceive(context: Context?, intent: Intent?) {
                            val map = mapOf(
                                "music" to intent?.getFloatExtra("music", 0f),
                                "ring" to intent?.getFloatExtra("ring", 0f),
                                "alarm" to intent?.getFloatExtra("alarm", 0f),
                                "notification" to intent?.getFloatExtra("notification", 0f),
                                "brightness" to intent?.getFloatExtra("brightness", 0f)
                            )
                            eventSink?.success(map)
                        }
                    }
                    val filter = IntentFilter("com.example.volume_controller.VOLUME_UPDATE")
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                        registerReceiver(volumeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                    } else {
                        registerReceiver(volumeReceiver, filter)
                    }
                }

                override fun onCancel(arguments: Any?) {
                    volumeReceiver?.let { unregisterReceiver(it) }
                    volumeReceiver = null
                    eventSink = null
                }
            }
        )
    }
}
