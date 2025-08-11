package id.bapenda.mdm

import android.content.pm.PackageManager
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.graphics.drawable.BitmapDrawable
import android.graphics.drawable.Drawable
import android.graphics.drawable.AdaptiveIconDrawable
import android.graphics.drawable.ColorDrawable
import android.graphics.Color
import android.graphics.Canvas
import android.util.Base64
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.ByteArrayOutputStream
import android.app.admin.DevicePolicyManager
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.preference.PreferenceManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "root/control"
    private lateinit var deviceAdminComponent: ComponentName
    private val REQUEST_CODE_ENABLE_ADMIN = 1001
    private var deviceAdminRequested = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        deviceAdminComponent = ComponentName(this, YourDeviceAdminReceiver::class.java)

        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!dpm.isAdminActive(deviceAdminComponent) && !deviceAdminRequested) {
            deviceAdminRequested = true
            requestDeviceAdmin()
        }
    }

    private fun requestDeviceAdmin() {
        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!dpm.isAdminActive(deviceAdminComponent)) {
            val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
            intent.putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, deviceAdminComponent)
            intent.putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Please enable device admin for security features.")
            startActivityForResult(intent, REQUEST_CODE_ENABLE_ADMIN)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQUEST_CODE_ENABLE_ADMIN) {
            if (resultCode == RESULT_OK) {
                Log.d("DeviceAdmin", "Device Admin enabled")
            } else {
                Log.d("DeviceAdmin", "Device Admin enable FAILED")
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "runCommand" -> {
                        val cmd = call.argument<String>("cmd")
                        if (cmd != null) {
                            result.success(runRootCommand(cmd))
                        } else {
                            result.error("INVALID_CMD", "Command is null", null)
                        }
                    }
                    "openApp" -> {
                        val packageName = call.argument<String>("package")
                        if (packageName != null) {
                            val launchIntent = context.packageManager.getLaunchIntentForPackage(packageName)
                            if (launchIntent != null) {
                                context.startActivity(launchIntent)
                                result.success("App opened")
                            } else {
                                result.error("APP_NOT_FOUND", "Cannot open app", null)
                            }
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    }
                    "getInstalledApps" -> {
                        result.success(getInstalledApps(packageManager))
                    }
                    "enableKiosk" -> {
                        val packageName = call.argument<String>("package")
                        if (packageName != null) {
                            enableKioskMode(packageName)
                            result.success("Kiosk Mode Enabled")
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    }
                    "enableKioskLauncher" -> {
                        enableKioskModeLauncher()
                        result.success("Kiosk Mode Launcher Enabled")
                    }
                    "disableKiosk" -> {
                        disableKioskMode()
                        result.success("Kiosk Mode Disabled")
                    }
                    "enableDeviceAdmin" -> {
                        requestDeviceAdmin()
                        result.success("Requesting device admin activation")
                    }
                    "startAppPinning" -> {
                        val packageName = call.argument<String>("package")
                        if (packageName != null) {
                            startAppPinning(packageName)
                            result.success("App pinning started")
                        } else {
                            result.error("INVALID_PACKAGE", "Package name is null", null)
                        }
                    }
                    "startForegroundService" -> {
                        val intent = Intent(this, ForegroundService::class.java)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            startForegroundService(intent)
                        } else {
                            startService(intent)
                        }
                        result.success("Foreground service started")
                    }
                    "setKioskTarget" -> {
                        val pkg = call.argument<String>("package")
                        if (pkg != null) {
                            val prefs = PreferenceManager.getDefaultSharedPreferences(context)
                            prefs.edit().putString("kiosk_target_package", pkg).apply()
                            result.success("Target package set: $pkg")
                        } else {
                            result.error("NO_PACKAGE", "Package name null", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enableKioskMode(packageName: String) {
        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        if (!dpm.isAdminActive(deviceAdminComponent)) {
            Log.e("KIOSK", "Device Admin belum aktif, tidak bisa enable kiosk")
            return
        }

        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        if (launchIntent == null) {
            Log.e("KIOSK", "App not found: $packageName")
            return
        }

        // Set paket yang diizinkan lock task (kiosk)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            dpm.setLockTaskPackages(deviceAdminComponent, arrayOf(packageName))
        }

        // Jalankan aplikasi target dan aktifkan lock task
        startActivity(launchIntent)
        Handler(Looper.getMainLooper()).postDelayed({
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                startLockTask()
                Log.d("KIOSK", "Kiosk Mode ON for $packageName")
            }
        }, 1000) // delay agar app target sempat terbuka
    }

    private fun enableKioskModeLauncher() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                startLockTask()
                Log.d("KIOSK", "Kiosk Mode ON")
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }


    private fun disableKioskMode() {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                stopLockTask()
                Log.d("KIOSK", "Kiosk Mode OFF")
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    fun startAppPinning(packageName: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            if (!isLockTaskPermitted()) {
                // Minta user untuk aktifkan manual pinning (pinning muncul dialog)
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    startActivity(launchIntent)

                    Handler(Looper.getMainLooper()).postDelayed({
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            startLockTask()
                        }
                    }, 1000)
                }

            } else {
                // Jika sudah diizinkan, bisa langsung lock
                val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
                if (launchIntent != null) {
                    startActivity(launchIntent)

                    Handler(Looper.getMainLooper()).postDelayed({
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            startLockTask()
                        }
                    }, 1000)
                }

            }
        }
    }

    fun isLockTaskPermitted(): Boolean {
        val dpm = getSystemService(DEVICE_POLICY_SERVICE) as DevicePolicyManager
        return dpm.isLockTaskPermitted(packageName)
    }

    private fun runRootCommand(command: String): String {
        return try {
            val process = Runtime.getRuntime().exec(arrayOf("su", "-c", command))
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = StringBuilder()
            var line: String?
            while (reader.readLine().also { line = it } != null) {
                output.append(line).append("\n")
            }
            process.waitFor()
            output.toString()
        } catch (e: Exception) {
            "Error: ${e.message}"
        }
    }

    private fun drawableToBitmap(drawable: Drawable): Bitmap {
        return when (drawable) {
            is BitmapDrawable -> drawable.bitmap
            is AdaptiveIconDrawable -> {
                val size = 108
                val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)

                val background = drawable.background ?: ColorDrawable(Color.TRANSPARENT)
                val foreground = drawable.foreground ?: ColorDrawable(Color.TRANSPARENT)

                background.setBounds(0, 0, size, size)
                background.draw(canvas)

                foreground.setBounds(0, 0, size, size)
                foreground.draw(canvas)

                bitmap
            }
            else -> {
                val size = 108
                val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
                val canvas = Canvas(bitmap)

                drawable.setBounds(0, 0, size, size)
                drawable.draw(canvas)

                bitmap
            }
        }
    }


    private fun getInstalledApps(pm: PackageManager): List<Map<String, Any>> {
        val apps = mutableListOf<Map<String, Any>>()
        val packages = pm.getInstalledApplications(PackageManager.GET_META_DATA)

        for (packageInfo in packages) {
            // Hanya tampilkan user apps (non-system)
            if (pm.getLaunchIntentForPackage(packageInfo.packageName) != null &&
                (packageInfo.flags and ApplicationInfo.FLAG_SYSTEM) == 0) {

                val appName = pm.getApplicationLabel(packageInfo).toString()
                val iconDrawable = pm.getApplicationIcon(packageInfo.packageName)
                val iconBitmap = drawableToBitmap(iconDrawable)

                val stream = ByteArrayOutputStream()
                iconBitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                val iconBase64 = Base64.encodeToString(stream.toByteArray(), Base64.NO_WRAP)

                apps.add(
                    mapOf(
                        "name" to appName,
                        "package" to packageInfo.packageName,
                        "icon" to iconBase64
                    )
                )
            }
        }
        return apps
    }

}
