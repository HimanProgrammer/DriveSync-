package com.drivesync.drivesync

import android.Manifest
import android.app.usage.StorageStatsManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import android.os.Environment
import android.os.storage.StorageManager
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import androidx.annotation.NonNull
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Native half of DriveSync on Android: storage volume capacities, the
 * readable roots the Dart scanner walks, and the SIM/carrier read that drives
 * the Jio Gemini Pro Pack check.
 */
class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "drivesync/native"
        const val REQ_PHONE = 4101
        const val REQ_STORAGE = 4102
    }

    private var pendingPermission: MethodChannel.Result? = null

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result -> handle(call, result) }
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getVolumes" -> result.success(volumes())
            "getReadableRoots" -> result.success(readableRoots())
            "getSimInfo" -> simInfo(result)
            "getDeviceName" -> result.success("${Build.MANUFACTURER} ${Build.MODEL}".trim())
            "requestPhonePermission" ->
                requestPermission(Manifest.permission.READ_PHONE_STATE, REQ_PHONE, result)
            "requestStoragePermission" -> requestStorage(result)
            else -> result.notImplemented()
        }
    }

    // ---------------------------------------------------------------- storage

    private fun volumes(): List<Map<String, Any>> {
        val out = mutableListOf<Map<String, Any>>()
        val storageManager = getSystemService(Context.STORAGE_SERVICE) as StorageManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val statsManager =
                getSystemService(Context.STORAGE_STATS_SERVICE) as StorageStatsManager
            for (volume in storageManager.storageVolumes) {
                val directory = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    volume.directory
                } else {
                    // Pre-R has no public directory accessor; fall back to the
                    // primary external dir for the primary volume only.
                    if (volume.isPrimary) Environment.getExternalStorageDirectory() else null
                } ?: continue

                // StorageStatsManager reports the *advertised* capacity for the
                // primary volume, which is what users recognise; StatFs on a
                // removable card is the only option there.
                var total: Long
                var free: Long
                try {
                    if (volume.isPrimary) {
                        val uuid = StorageManager.UUID_DEFAULT
                        total = statsManager.getTotalBytes(uuid)
                        free = statsManager.getFreeBytes(uuid)
                    } else {
                        total = directory.totalSpace
                        free = directory.usableSpace
                    }
                } catch (e: Exception) {
                    total = directory.totalSpace
                    free = directory.usableSpace
                }
                if (total <= 0L) continue

                out.add(
                    mapOf(
                        "id" to (volume.uuid ?: if (volume.isPrimary) "primary" else directory.path),
                        "label" to (volume.getDescription(this)
                            ?: if (volume.isPrimary) "Internal storage" else "SD card"),
                        "path" to directory.path,
                        "totalBytes" to total,
                        "freeBytes" to free,
                        "isRemovable" to volume.isRemovable,
                        "isPrimary" to volume.isPrimary
                    )
                )
            }
        }

        if (out.isEmpty()) {
            val dir = Environment.getExternalStorageDirectory()
            out.add(
                mapOf(
                    "id" to "primary",
                    "label" to "Internal storage",
                    "path" to dir.path,
                    "totalBytes" to dir.totalSpace,
                    "freeBytes" to dir.usableSpace,
                    "isRemovable" to false,
                    "isPrimary" to true
                )
            )
        }
        return out
    }

    /**
     * Roots the Dart scanner can actually walk. Scoped storage means shared
     * media plus our own app dirs; anything else throws on listing, and the
     * scanner records it as skipped rather than failing the scan.
     */
    private fun readableRoots(): List<String> {
        val roots = linkedSetOf<String>()
        val shared = Environment.getExternalStorageDirectory()
        if (shared != null && shared.canRead()) {
            for (name in listOf(
                Environment.DIRECTORY_DCIM,
                Environment.DIRECTORY_PICTURES,
                Environment.DIRECTORY_MOVIES,
                Environment.DIRECTORY_MUSIC,
                Environment.DIRECTORY_DOWNLOADS,
                Environment.DIRECTORY_DOCUMENTS
            )) {
                val dir = File(shared, name)
                if (dir.isDirectory && dir.canRead()) roots.add(dir.absolutePath)
            }
            // With MANAGE_EXTERNAL_STORAGE (or pre-R legacy access) the whole
            // shared volume is readable, which gives a far better picture.
            if (shared.canRead() && shared.list() != null) roots.add(shared.absolutePath)
        }
        getExternalFilesDirs(null).filterNotNull().forEach {
            if (it.canRead()) roots.add(it.absolutePath)
        }
        return roots.toList()
    }

    // -------------------------------------------------------------------- SIM

    private fun simInfo(result: MethodChannel.Result) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.READ_PHONE_STATE)
            != PackageManager.PERMISSION_GRANTED
        ) {
            // Null (not an error, not an empty list) so Dart can distinguish
            // "not checked" from "no Jio SIM".
            result.success(null)
            return
        }

        val sims = mutableListOf<Map<String, Any?>>()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                val subs = getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE)
                        as SubscriptionManager
                subs.activeSubscriptionInfoList?.forEach { info ->
                    sims.add(
                        mapOf(
                            "carrierName" to (info.carrierName?.toString() ?: ""),
                            "operatorNumeric" to operatorNumeric(info),
                            "slotIndex" to info.simSlotIndex
                        )
                    )
                }
            }
            if (sims.isEmpty()) {
                val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
                sims.add(
                    mapOf(
                        "carrierName" to (tm.simOperatorName ?: ""),
                        "operatorNumeric" to (tm.simOperator ?: ""),
                        "slotIndex" to 0
                    )
                )
            }
            result.success(sims)
        } catch (e: SecurityException) {
            result.success(null)
        }
    }

    /** MCC+MNC, e.g. "405854" for a Jio SIM. */
    @Suppress("DEPRECATION")
    private fun operatorNumeric(info: android.telephony.SubscriptionInfo): String =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${info.mccString ?: ""}${info.mncString ?: ""}"
        } else {
            "%d%02d".format(info.mcc, info.mnc)
        }

    // ------------------------------------------------------------ permissions

    private fun requestStorage(result: MethodChannel.Result) {
        val permission = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            Manifest.permission.READ_MEDIA_IMAGES
        } else {
            Manifest.permission.READ_EXTERNAL_STORAGE
        }
        requestPermission(permission, REQ_STORAGE, result)
    }

    private fun requestPermission(
        permission: String,
        requestCode: Int,
        result: MethodChannel.Result
    ) {
        if (ContextCompat.checkSelfPermission(this, permission)
            == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermission != null) {
            result.success(false) // one prompt at a time
            return
        }
        pendingPermission = result
        ActivityCompat.requestPermissions(this, arrayOf(permission), requestCode)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQ_PHONE || requestCode == REQ_STORAGE) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingPermission?.success(granted)
            pendingPermission = null
        }
    }
}
