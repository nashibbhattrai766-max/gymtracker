package com.nash.gymtracker.gymtracker

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.content.ContextCompat
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import java.time.LocalDate

// FlutterFragmentActivity (not FlutterActivity) — the Health Connect permission
// screen needs an ActivityResult launcher.
class MainActivity : FlutterFragmentActivity() {

    private val scope = MainScope()
    private var launchTab: String? = null

    private var pendingHealthResult: MethodChannel.Result? = null
    private val healthPermissionLauncher =
        registerForActivityResult(PermissionController.createRequestPermissionResultContract()) { granted ->
            pendingHealthResult?.success(granted.toList())
            pendingHealthResult = null
        }

    private var scale: VitafitScale? = null
    private var scaleSink: EventChannel.EventSink? = null

    private var pendingBtResult: MethodChannel.Result? = null
    private val btPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { granted ->
            pendingBtResult?.success(granted.values.all { it })
            pendingBtResult = null
        }

    private var pendingNotifResult: MethodChannel.Result? = null
    private val notifPermissionLauncher =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { ok ->
            pendingNotifResult?.success(ok)
            pendingNotifResult = null
        }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        launchTab = intent?.getStringExtra(Reminders.EXTRA_OPEN_TAB)
        Reminders.scheduleAll(this)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(Reminders.EXTRA_OPEN_TAB)?.let { launchTab = it }
    }

    override fun onDestroy() {
        scale?.stop()
        scope.cancel()
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger

        // ── Reminders ───────────────────────────────────────────────────────
        MethodChannel(messenger, "gymtracker/reminders").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
                        ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) ==
                        PackageManager.PERMISSION_GRANTED
                    ) {
                        result.success(true)
                    } else {
                        pendingNotifResult = result
                        notifPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                }
                "getSettings" -> result.success(Reminders.settings(this))
                "setSettings" -> {
                    @Suppress("UNCHECKED_CAST")
                    Reminders.saveSettings(this, call.arguments as Map<String, Boolean>)
                    Reminders.scheduleAll(this)
                    result.success(null)
                }
                "test" -> { Reminders.showTest(this); result.success(null) }
                "consumeLaunchTab" -> { result.success(launchTab); launchTab = null }
                else -> result.notImplemented()
            }
        }

        // ── System: open links (YouTube videos) in their app / the browser ──────
        MethodChannel(messenger, "gymtracker/system").setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> {
                    try {
                        startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url"))))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ── Vitafit scale (Bluetooth LE) ───────────────────────────────────────
        EventChannel(messenger, "gymtracker/scale/events").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink) { scaleSink = events }
            override fun onCancel(arguments: Any?) { scaleSink = null }
        })
        MethodChannel(messenger, "gymtracker/scale").setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    val needed = bluetoothPermissions().filter {
                        ContextCompat.checkSelfPermission(this, it) != PackageManager.PERMISSION_GRANTED
                    }
                    if (needed.isEmpty()) {
                        result.success(true)
                    } else {
                        pendingBtResult = result
                        btPermissionLauncher.launch(needed.toTypedArray())
                    }
                }
                "start" -> {
                    val s = scale ?: VitafitScale(this) { event -> scaleSink?.success(event) }.also { scale = it }
                    s.start()
                    result.success(null)
                }
                "stop" -> { scale?.stop(); result.success(null) }
                else -> result.notImplemented()
            }
        }

        // ── Health Connect ──────────────────────────────────────────────────
        MethodChannel(messenger, "gymtracker/health").setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> scope.launch {
                    val sdk = HealthReader.sdkStatus(this@MainActivity)
                    if (sdk != HealthConnectClient.SDK_AVAILABLE) {
                        result.success(mapOf(
                            "sdk" to if (sdk == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED)
                                "update_required" else "unavailable",
                        ))
                        return@launch
                    }
                    try {
                        val reader = HealthReader(this@MainActivity)
                        val granted = reader.grantedPermissions()
                        result.success(mapOf(
                            "sdk" to "available",
                            "granted" to HealthReader.PERMISSIONS.count { it in granted },
                            "required" to HealthReader.PERMISSIONS.size,
                            "background" to (HealthReader.BACKGROUND in granted),
                            "backgroundSupported" to reader.backgroundSupported(),
                        ))
                    } catch (e: Exception) {
                        result.error("STATUS_FAILED", e.message, null)
                    }
                }
                "requestPermissions" -> {
                    if (HealthReader.sdkStatus(this) != HealthConnectClient.SDK_AVAILABLE) {
                        result.error("UNAVAILABLE", "Health Connect is not available", null)
                    } else {
                        val perms = HealthReader.PERMISSIONS.toMutableSet()
                        if (HealthReader(this).backgroundSupported()) perms += HealthReader.BACKGROUND
                        pendingHealthResult = result
                        healthPermissionLauncher.launch(perms)
                    }
                }
                "readDay" -> scope.launch {
                    try {
                        val date = LocalDate.parse(call.argument<String>("date"))
                        result.success(HealthReader(this@MainActivity).readDay(date))
                    } catch (e: Exception) {
                        result.error("READ_FAILED", e.message, null)
                    }
                }
                "openSettings" -> {
                    val sdk = HealthReader.sdkStatus(this)
                    val intent = if (sdk == HealthConnectClient.SDK_AVAILABLE) {
                        Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)
                    } else {
                        Intent(Intent.ACTION_VIEW,
                            Uri.parse("market://details?id=com.google.android.apps.healthdata"))
                    }
                    try { startActivity(intent) } catch (_: Exception) {}
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun bluetoothPermissions(): List<String> =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            listOf(Manifest.permission.BLUETOOTH_SCAN, Manifest.permission.BLUETOOTH_CONNECT)
        } else {
            listOf(Manifest.permission.ACCESS_FINE_LOCATION)
        }
}
