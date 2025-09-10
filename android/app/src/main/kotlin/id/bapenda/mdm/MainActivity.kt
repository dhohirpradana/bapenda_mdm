package id.bapenda.mdm

import android.view.MotionEvent
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
import android.app.ActivityManager
import androidx.core.content.ContextCompat
import android.net.Uri
import android.provider.Settings

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

        // Request izin tampil di atas aplikasi lain
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!Settings.canDrawOverlays(this)) {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:$packageName")
                )
                startActivityForResult(intent, 1234) // requestCode bebas
            }
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
                    "rebootDevice" -> {
                        rebootDevice()
                        result.success("Reboot command executed")
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
                    "sendResetIdle" -> {
                        val intent = Intent("id.bapenda.mdm.RESET_IDLE")
                        sendBroadcast(intent)
                        result.success("Idle timer reset")
                    }
                    "enableDeviceAdmin" -> {
                        requestDeviceAdmin()
                        result.success("Requesting device admin activation")
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
                    else -> result.notImplemented()
                }
            }
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

    fun rebootDevice() {
        try {
            Runtime.getRuntime().exec(arrayOf("su", "-c", "reboot"))
        } catch (e: Exception) {
            Log.e("ForegroundService", "Failed to reboot: ${e.message}")
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
