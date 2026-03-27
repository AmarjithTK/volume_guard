package com.example.volume_controller

import android.accessibilityservice.AccessibilityService
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothA2dp
import android.database.ContentObserver
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class VolumeControllerService : AccessibilityService() {

    private val CHANNEL_ID = "VolumeControllerChannel"
    private val NOTIFICATION_ID = 1

    private lateinit var audioManager: AudioManager
    private lateinit var settingsObserver: SettingsObserver

    override fun onServiceConnected() {
        super.onServiceConnected()
        audioManager = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        createNotificationChannel()

        settingsObserver = SettingsObserver(Handler(Looper.getMainLooper()))
        contentResolver.registerContentObserver(
            Settings.System.CONTENT_URI, true, settingsObserver
        )

        val filter = IntentFilter().apply {
            addAction("ACTION_TOGGLE_MEDIA_LOCK")
            addAction("ACTION_TOGGLE_RING_LOCK")
            addAction("ACTION_TOGGLE_BT_LOCK")
        }
        
        val btFilter = IntentFilter().apply {
            addAction(BluetoothDevice.ACTION_ACL_CONNECTED)
            addAction(Intent.ACTION_HEADSET_PLUG)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(actionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
            registerReceiver(btReceiver, btFilter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(actionReceiver, filter)
            registerReceiver(btReceiver, btFilter)
        }

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(NOTIFICATION_ID, buildNotification(), android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)
        } else {
            startForeground(NOTIFICATION_ID, buildNotification())
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return super.onStartCommand(intent, flags, startId)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Required method for AccessibilityService
    }

    override fun onInterrupt() {
        // Required method for AccessibilityService
    }

    override fun onKeyEvent(event: KeyEvent?): Boolean {
        // Optionally intercept physical volume keys to block changes instantly
        return super.onKeyEvent(event)
    }

    override fun onDestroy() {
        super.onDestroy()
        contentResolver.unregisterContentObserver(settingsObserver)
        unregisterReceiver(actionReceiver)
        unregisterReceiver(btReceiver)
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                "Volume Controller Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(serviceChannel)
        }
    }

    private fun buildNotification(): Notification {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val mediaLocked = prefs.getBoolean("flutter.media_lock_enabled", false)
        val ringLocked = prefs.getBoolean("flutter.ring_lock_enabled", false)
        val btLocked = prefs.getBoolean("flutter.bt_lock_enabled", false)

        val mediaIntent = Intent("ACTION_TOGGLE_MEDIA_LOCK")
        val mediaPendingIntent = PendingIntent.getBroadcast(
            this, 0, mediaIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val ringIntent = Intent("ACTION_TOGGLE_RING_LOCK")
        val ringPendingIntent = PendingIntent.getBroadcast(
            this, 1, ringIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        
        val btIntent = Intent("ACTION_TOGGLE_BT_LOCK")
        val btPendingIntent = PendingIntent.getBroadcast(
            this, 2, btIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            Notification.Builder(this)
        }

        return builder
            .setContentTitle("Volume Controller Active")
            .setContentText("Locks are monitoring in background")
            .setSmallIcon(applicationInfo.icon)
            .addAction(Notification.Action.Builder(null, if (mediaLocked) "Unlock Media" else "Lock Media", mediaPendingIntent).build())
            .addAction(Notification.Action.Builder(null, if (ringLocked) "Unlock Ring" else "Lock Ring", ringPendingIntent).build())
            .addAction(Notification.Action.Builder(null, if (btLocked) "Unlock BT" else "Lock BT", btPendingIntent).build())
            .setOngoing(true)
            .build()
    }

    private fun updateNotification() {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(NOTIFICATION_ID, buildNotification())
    }

    private val actionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
            val editor = prefs.edit()
            when (intent?.action) {
                "ACTION_TOGGLE_MEDIA_LOCK" -> {
                    val current = prefs.getBoolean("flutter.media_lock_enabled", false)
                    editor.putBoolean("flutter.media_lock_enabled", !current)
                    editor.apply()
                    updateNotification()
                }
                "ACTION_TOGGLE_RING_LOCK" -> {
                    val current = prefs.getBoolean("flutter.ring_lock_enabled", false)
                    editor.putBoolean("flutter.ring_lock_enabled", !current)
                    editor.apply()
                    updateNotification()
                }
                "ACTION_TOGGLE_BT_LOCK" -> {
                    val current = prefs.getBoolean("flutter.bt_lock_enabled", false)
                    editor.putBoolean("flutter.bt_lock_enabled", !current)
                    editor.apply()
                    updateNotification()
                }
            }
        }
    }
    
    // Receiver for Bluetooth & WIRED HEADSET events
    private val btReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action
            if (action == BluetoothDevice.ACTION_ACL_CONNECTED || action == Intent.ACTION_HEADSET_PLUG) {
                // If it's headset plug, we must verify state=1 (connected)
                if (action == Intent.ACTION_HEADSET_PLUG) {
                    val state = intent.getIntExtra("state", 0)
                    if (state == 0) return // Disconnected
                }
                
                val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
                val btLocked = prefs.getBoolean("flutter.bt_lock_enabled", false)
                if (btLocked) {
                    val initialVolPercent = prefs.getLong("flutter.bt_launch_volume", -1L).toInt()
                    if (initialVolPercent != -1) {
                        // Delay slightly to let Android register the new stream route, then clamp
                        Handler(Looper.getMainLooper()).postDelayed({
                            val maxVol = audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                            val targetValue = (initialVolPercent * maxVol) / 100
                            val currentVol = audioManager.getStreamVolume(AudioManager.STREAM_MUSIC)
                            // Usually Bluetooth launch logic forces it down to prevent ear drum rupture
                            if (currentVol > targetValue) {
                                audioManager.setStreamVolume(AudioManager.STREAM_MUSIC, targetValue, 0)
                            }
                        }, 500)
                    }
                }
            }
        }
    }

    private inner class SettingsObserver(handler: Handler) : ContentObserver(handler) {
        override fun onChange(selfChange: Boolean, uri: Uri?) {
            super.onChange(selfChange, uri)
            checkAndEnforceLocks()
            broadcastCurrentVolumes()
        }
    }
    
    private fun broadcastCurrentVolumes() {
        val intent = Intent("com.example.volume_controller.VOLUME_UPDATE")
        intent.putExtra("music", (audioManager.getStreamVolume(AudioManager.STREAM_MUSIC).toFloat() / audioManager.getStreamMaxVolume(AudioManager.STREAM_MUSIC)) * 100)
        intent.putExtra("ring", (audioManager.getStreamVolume(AudioManager.STREAM_RING).toFloat() / audioManager.getStreamMaxVolume(AudioManager.STREAM_RING)) * 100)
        intent.putExtra("alarm", (audioManager.getStreamVolume(AudioManager.STREAM_ALARM).toFloat() / audioManager.getStreamMaxVolume(AudioManager.STREAM_ALARM)) * 100)
        intent.putExtra("notification", (audioManager.getStreamVolume(AudioManager.STREAM_NOTIFICATION).toFloat() / audioManager.getStreamMaxVolume(AudioManager.STREAM_NOTIFICATION)) * 100)
        try {
            intent.putExtra("brightness", (Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS).toFloat() / 255f) * 100)
        } catch (e: Exception) {}
        sendBroadcast(intent)
    }

    private fun checkAndEnforceLocks() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

        fun checkStream(stream: Int, enabledKey: String, minKey: String, maxKey: String) {
            if (prefs.getBoolean("flutter.$enabledKey", false)) {
                val minPercent = prefs.getLong("flutter.$minKey", -1L).toInt()
                val maxPercent = prefs.getLong("flutter.$maxKey", -1L).toInt()

                if (minPercent != -1 && maxPercent != -1) {
                    val maxVol = audioManager.getStreamMaxVolume(stream)
                    val minValue = (minPercent * maxVol) / 100
                    val maxValue = (maxPercent * maxVol) / 100
                    val currentVol = audioManager.getStreamVolume(stream)

                    if (currentVol < minValue) {
                        audioManager.setStreamVolume(stream, minValue, 0)
                    } else if (currentVol > maxValue) {
                        audioManager.setStreamVolume(stream, maxValue, 0)
                    }
                }
            }
        }

        checkStream(AudioManager.STREAM_MUSIC, "media_lock_enabled", "media_lock_min", "media_lock_max")
        checkStream(AudioManager.STREAM_RING, "ring_lock_enabled", "ring_lock_min", "ring_lock_max")
        checkStream(AudioManager.STREAM_ALARM, "alarm_lock_enabled", "alarm_lock_min", "alarm_lock_max")
        checkStream(AudioManager.STREAM_NOTIFICATION, "notif_lock_enabled", "notif_lock_min", "notif_lock_max")

        // Brightness Lock
        if (prefs.getBoolean("flutter.brightness_min_lock_enabled", false)) {
            val lockedPercentageMin = prefs.getLong("flutter.brightness_min_value", -1L).toInt()
            val lockedPercentageMax = prefs.getLong("flutter.brightness_max_value", -1L).toInt()
            if (lockedPercentageMin != -1 && Settings.System.canWrite(this)) {
                try {
                    val minValue = (lockedPercentageMin * 255) / 100
                    val maxValue = (lockedPercentageMax * 255) / 100
                    val currentBrightness = Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS)
                    
                    if (currentBrightness < minValue) {
                        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, minValue)
                    } else if (currentBrightness > maxValue && maxValue > minValue) {
                        Settings.System.putInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS, maxValue)
                    }
                } catch (e: Exception) {}
            }
        }
    }
}
