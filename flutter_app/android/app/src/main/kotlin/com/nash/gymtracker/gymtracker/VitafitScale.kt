package com.nash.gymtracker.gymtracker

import android.annotation.SuppressLint
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.BluetoothStatusCodes
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.Context
import android.os.Build
import android.os.Handler
import android.os.Looper
import java.util.UUID

/**
 * Vitafit "Body Fat" scale (VT701, sold with the Vitafit / Fitdays app) over Bluetooth LE.
 *
 * Protocol as documented by the openScale project (VitafitVT701Handler):
 *  - Service 0xFFF0; notify characteristic 0xFFF1; write characteristic 0xFFF2.
 *  - Frames: [hdr][len][0x26][type][data…][xor][0xAA]; hdr 0x5A scale→phone, 0xA5 phone→scale;
 *    len counts every byte after itself; xor covers len … last data byte.
 *  - Type 0x10 = weight: byte 4 is 0x02 once stable, bytes 8..9 = weight in 0.01 kg (big-endian).
 *  - Acking the stable weight makes the scale measure impedance → type 0x11, bytes 9..10 = ohms.
 *
 * The scale only reports weight + impedance; body composition is calculated in Dart
 * (lib/services/body_composition.dart). Events go to Flutter through [emit].
 */
@SuppressLint("MissingPermission") // permissions are requested by MainActivity before start()
class VitafitScale(private val ctx: Context, private val emit: (Map<String, Any?>) -> Unit) {

    companion object {
        private val SERVICE: UUID = uuid16(0xFFF0)
        private val NOTIFY: UUID = uuid16(0xFFF1)
        private val WRITE: UUID = uuid16(0xFFF2)
        private val CCCD: UUID = uuid16(0x2902)

        private const val HEADER_SCALE = 0x5A
        private const val HEADER_PHONE = 0xA5
        private const val PRODUCT_ID = 0x26
        private const val TRAILER = 0xAA
        private const val TYPE_WEIGHT = 0x10
        private const val TYPE_IMPEDANCE = 0x11
        private const val STABLE = 0x02

        private const val SCAN_TIMEOUT_MS = 60_000L
        private const val IMPEDANCE_TIMEOUT_MS = 6_000L

        private fun uuid16(v: Int): UUID =
            UUID.fromString(String.format("0000%04x-0000-1000-8000-00805f9b34fb", v))

        private val Byte.u: Int get() = toInt() and 0xFF

        private fun xor(frame: ByteArray, from: Int, toExclusive: Int): Int {
            var acc = 0
            for (i in from until toExclusive) acc = acc xor frame[i].u
            return acc
        }

        fun isValidFrame(f: ByteArray): Boolean =
            f.size >= 6 && f[0].u == HEADER_SCALE && f[2].u == PRODUCT_ID &&
                f[f.size - 1].u == TRAILER && f[1].u == f.size - 2 &&
                xor(f, 1, f.size - 2) == f[f.size - 2].u

        fun command(type: Int, data: ByteArray): ByteArray {
            val f = ByteArray(data.size + 6)
            f[0] = HEADER_PHONE.toByte()
            f[1] = (data.size + 4).toByte()
            f[2] = PRODUCT_ID.toByte()
            f[3] = type.toByte()
            data.copyInto(f, 4)
            f[f.size - 2] = xor(f, 1, f.size - 2).toByte()
            f[f.size - 1] = TRAILER.toByte()
            return f
        }
    }

    private val main = Handler(Looper.getMainLooper())
    private val adapter = ctx.getSystemService(BluetoothManager::class.java)?.adapter

    private var scanning = false
    private var gatt: BluetoothGatt? = null
    private var device: BluetoothDevice? = null
    private var writeChar: BluetoothGattCharacteristic? = null
    private var connectRetries = 0

    private var stableWeight: Double? = null
    private var finished = true

    // GATT allows one outstanding operation at a time — queue writes.
    private val ops = ArrayDeque<() -> Unit>()
    private var opBusy = false

    // ── Public API ──────────────────────────────────────────────────────────

    fun start() {
        stop()
        finished = false
        stableWeight = null
        connectRetries = 0

        val a = adapter
        if (a == null || !a.isEnabled) return fail("Bluetooth is off. Turn it on and try again.")
        val scanner = a.bluetoothLeScanner ?: return fail("Bluetooth is off. Turn it on and try again.")

        status("Step on the scale to wake it up…")
        scanning = true
        scanner.startScan(null, ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scanCallback)
        main.postDelayed(scanTimeout, SCAN_TIMEOUT_MS)
    }

    fun stop() {
        main.removeCallbacksAndMessages(null)
        if (scanning) {
            scanning = false
            try { adapter?.bluetoothLeScanner?.stopScan(scanCallback) } catch (_: Exception) {}
        }
        ops.clear()
        opBusy = false
        gatt?.let { try { it.disconnect(); it.close() } catch (_: Exception) {} }
        gatt = null
        writeChar = null
    }

    // ── Scan ────────────────────────────────────────────────────────────────

    private val scanTimeout = Runnable {
        fail("Couldn't find the scale. Step on it to wake it up, and make sure the Vitafit app is closed.")
    }

    private val scanCallback = object : ScanCallback() {
        override fun onScanResult(callbackType: Int, result: ScanResult) {
            val name = result.scanRecord?.deviceName ?: return
            if (!scanning || !name.startsWith("Vitafit", ignoreCase = true)) return
            scanning = false
            main.removeCallbacks(scanTimeout)
            try { adapter?.bluetoothLeScanner?.stopScan(this) } catch (_: Exception) {}
            device = result.device
            status("Scale found — connecting…")
            main.post { connect() }
        }

        override fun onScanFailed(errorCode: Int) {
            fail("Bluetooth scan failed (code $errorCode). Try again.")
        }
    }

    private fun connect() {
        val d = device ?: return
        gatt = d.connectGatt(ctx, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
    }

    // ── GATT ────────────────────────────────────────────────────────────────

    private val gattCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(g: BluetoothGatt, statusCode: Int, newState: Int) {
            main.post {
                if (finished) return@post
                if (newState == BluetoothProfile.STATE_CONNECTED && statusCode == BluetoothGatt.GATT_SUCCESS) {
                    g.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    g.close()
                    if (gatt == g) gatt = null
                    // 133 is Android's generic "connection failed"; one or two retries usually fix it
                    if (statusCode == 133 && connectRetries < 2 && stableWeight == null) {
                        connectRetries++
                        main.postDelayed({ connect() }, 600)
                    } else {
                        stableWeight?.let { finish(it, null) }
                            ?: fail("The scale disconnected before a reading was taken. Try again.")
                    }
                }
            }
        }

        override fun onServicesDiscovered(g: BluetoothGatt, statusCode: Int) {
            main.post {
                if (finished) return@post
                val service = g.getService(SERVICE)
                val notify = service?.getCharacteristic(NOTIFY)
                writeChar = service?.getCharacteristic(WRITE)
                if (notify == null || writeChar == null) {
                    return@post fail("This doesn't look like a supported Vitafit scale.")
                }
                g.setCharacteristicNotification(notify, true)
                notify.getDescriptor(CCCD)?.let { writeDescriptor(it, BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE) }
                // Same static hello the Vitafit app sends; the scale then streams weight frames
                write(command(0x33, byteArrayOf(0x00)))
                write(command(0x44, byteArrayOf()))
                write(command(0x17, byteArrayOf(0x01)))
                status("Connected — stay on the scale…")
            }
        }

        override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, statusCode: Int) {
            main.post { opDone() }
        }

        override fun onCharacteristicWrite(g: BluetoothGatt, c: BluetoothGattCharacteristic, statusCode: Int) {
            main.post { opDone() }
        }

        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic, value: ByteArray) {
            if (c.uuid == NOTIFY) main.post { onFrame(value) }
        }

        @Deprecated("Used on Android 12 and below")
        override fun onCharacteristicChanged(g: BluetoothGatt, c: BluetoothGattCharacteristic) {
            @Suppress("DEPRECATION")
            val value = c.value ?: return
            if (c.uuid == NOTIFY) main.post { onFrame(value.copyOf()) }
        }
    }

    // ── Protocol ────────────────────────────────────────────────────────────

    private fun onFrame(f: ByteArray) {
        if (finished || !isValidFrame(f)) return
        when (f[3].u) {
            TYPE_WEIGHT -> {
                if (f.size < 12) return
                val kg = ((f[8].u shl 8) or f[9].u) / 100.0
                val stable = f[4].u == STABLE
                if (stableWeight == null) emit(mapOf("type" to "live", "weightKg" to kg, "stable" to stable))
                if (stable && stableWeight == null && kg > 0) {
                    stableWeight = kg
                    status("Measuring body composition — stay still, barefoot…")
                    // Ack the stable weight; this triggers the impedance measurement
                    write(command(TYPE_WEIGHT, byteArrayOf(STABLE.toByte())))
                    main.postDelayed({ if (!finished) finish(kg, null) }, IMPEDANCE_TIMEOUT_MS)
                }
            }
            TYPE_IMPEDANCE -> {
                val kg = stableWeight ?: return
                if (f.size < 13) return
                val ohm = (f[9].u shl 8) or f[10].u
                if (ohm <= 0) return
                write(command(TYPE_IMPEDANCE, byteArrayOf(0x00)))
                finish(kg, ohm)
            }
        }
    }

    private fun finish(weightKg: Double, impedanceOhm: Int?) {
        if (finished) return
        finished = true
        emit(mapOf("type" to "result", "weightKg" to weightKg, "impedanceOhm" to impedanceOhm))
        main.removeCallbacksAndMessages(null)
        main.postDelayed({ stop() }, 400) // let the final ack go out
    }

    private fun fail(message: String) {
        if (finished) return
        finished = true
        emit(mapOf("type" to "error", "message" to message))
        stop()
    }

    private fun status(message: String) = emit(mapOf("type" to "status", "message" to message))

    // ── Serialised GATT writes ──────────────────────────────────────────────

    private fun enqueue(op: () -> Unit) {
        ops.addLast(op)
        if (!opBusy) nextOp()
    }

    private fun nextOp() {
        val op = ops.removeFirstOrNull() ?: run { opBusy = false; return }
        opBusy = true
        op()
    }

    private fun opDone() = nextOp()

    private fun write(bytes: ByteArray) = enqueue {
        val g = gatt
        val c = writeChar
        if (g == null || c == null) return@enqueue opDone()
        val type = if (c.properties and BluetoothGattCharacteristic.PROPERTY_WRITE != 0)
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeCharacteristic(c, bytes, type) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run { c.writeType = type; c.value = bytes; g.writeCharacteristic(c) }
        }
        if (!ok) opDone()
    }

    private fun writeDescriptor(d: BluetoothGattDescriptor, value: ByteArray) = enqueue {
        val g = gatt ?: return@enqueue opDone()
        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            g.writeDescriptor(d, value) == BluetoothStatusCodes.SUCCESS
        } else {
            @Suppress("DEPRECATION")
            run { d.value = value; g.writeDescriptor(d) }
        }
        if (!ok) opDone()
    }
}
