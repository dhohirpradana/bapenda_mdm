package id.bapenda.mdm

import android.app.*
import android.content.*
import android.graphics.*
import android.os.*
import android.util.Log
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import java.io.File
import org.json.JSONObject
import java.util.Timer
import java.util.TimerTask
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

class ForegroundService : Service() {
    private var timer: Timer? = null
    private var methodChannel: MethodChannel? = null
    private var flutterEngine: FlutterEngine? = null

    private val TAG = "ForegroundService"
    private val CHANNEL_ID = "BapendaForegroundServiceChannel"
    private var windowManager: WindowManager? = null
    private var overlayView: View? = null
    private var handler: Handler? = null
    private var runnable: Runnable? = null
    private var isScreensaverShown = false

    // Screensaver vars
    private var isScreensaverEnabled: Boolean = false
    private var screensaverType: String? = null
    private var screensaverText: String? = null
    private var screensaverImageFile: File? = null
    private var screensaverVideoFile: File? = null
    private var interval: Long = 10_000

    override fun onBind(intent: Intent?): IBinder? = null

    private var fileObserver: FileObserver? = null

    override fun onCreate() {
        super.onCreate()
        Log.d(TAG, "Service onCreate")
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        handler = Handler(Looper.getMainLooper())

        // Foreground notification
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Foreground Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Bapenda MDM")
            .setContentText("Screensaver service aktif")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .build()

        startForeground(1, notification)

        // Setup FlutterEngine untuk panggil Dart
        // flutterEngine = FlutterEngine(this).apply {
        //     dartExecutor.executeDartEntrypoint(
        //         DartExecutor.DartEntrypoint.createDefault()
        //     )
        // }
        // methodChannel = MethodChannel(flutterEngine!!.dartExecutor.binaryMessenger, "foreground_service_channel")

        // // Timer tiap 1 menit untuk panggil restoreAuth di Dart
        // timer = Timer()
        // timer?.scheduleAtFixedRate(object : TimerTask() {
        //     override fun run() {
        //         Handler(Looper.getMainLooper()).post {
        //             Log.d(TAG, "Invoke restoreAuth() via MethodChannel (main thread)")
        //             methodChannel?.invokeMethod("restoreAuth", null)
        //         }
        //     }
        // }, 0, 60 * 1000)

        runnable = Runnable { showOverlay() }
        resetIdleTimer()

        // Receiver untuk reset
        val filter = IntentFilter("id.bapenda.mdm.RESET_IDLE")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(resetReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(resetReceiver, filter)
        }
        Log.d(TAG, "Service onCreate finished, receiver registered")

        // ==== FILE OBSERVER ====
        val dir = getExternalFilesDir(null)
        val configFile = File(dir, "screensaver_config.json")
        fileObserver = object : FileObserver(configFile.path, CLOSE_WRITE) {
            override fun onEvent(event: Int, path: String?) {
                if (event == CLOSE_WRITE) {
                    Log.d(TAG, "screensaver_config.json changed, reloading...")

                    // Jalankan di main thread
                    handler?.post {
                        loadScreensaverConfig()
                    }
                }
            }
        }
        fileObserver?.startWatching()
    }

    override fun onDestroy() {
        super.onDestroy()
        Log.d(TAG, "Service onDestroy")
        handler?.removeCallbacks(runnable!!)
        unregisterReceiver(resetReceiver)
        hideOverlay()
        timer?.cancel()
        flutterEngine?.destroy()
    }

    private val resetReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            Log.d(TAG, "RESET_IDLE broadcast received")
            resetIdleTimer()
        }
    }

    private fun resetIdleTimer() {
        Log.d(TAG, "Resetting idle timer")
        handler?.removeCallbacks(runnable!!)
        handler?.postDelayed(runnable!!, interval)
        if (isScreensaverShown) {
            Log.d(TAG, "Hiding overlay due to idle reset")
            hideOverlay()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.d(TAG, "onStartCommand called")
        loadScreensaverConfig()
        return START_STICKY
    }

    private fun loadScreensaverConfig() {
        val dir = getExternalFilesDir(null) ?: return
        val file = File(dir, "screensaver_config.json")
        Log.d(TAG, "Loading screensaver config from: ${file.path}")
        if (!file.exists()) {
            Log.d(TAG, "Screensaver config file does not exist")
            return
        }

        try {
            val json = JSONObject(file.readText())
            isScreensaverEnabled = json.optBoolean("isEnabled", false)
            screensaverType = json.optString("type")
            screensaverText = json.optString("text")
            interval = json.optLong("interval", 10_000).coerceAtLeast(10_000)
            screensaverImageFile = json.optString("imagePath")
                .takeIf { path: String -> path.isNotEmpty() }
                ?.let { path: String -> File(path) }
            screensaverVideoFile = json.optString("videoPath")
                .takeIf { path: String -> path.isNotEmpty() }
                ?.let { path: String -> File(path) }

            Log.d(TAG, "Screensaver loaded: enabled=$isScreensaverEnabled, type=$screensaverType, text=$screensaverText, interval=$interval")
            Log.d(TAG, "Image file: ${screensaverImageFile?.path}, Video file: ${screensaverVideoFile?.path}")

            if (isScreensaverShown) hideOverlay()
            resetIdleTimer()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load screensaver config", e)
        }
    }

    private fun showOverlay() {
        Log.d(TAG, "Attempting to show overlay")
        if (!isScreensaverEnabled) {
            Log.d(TAG, "Screensaver disabled, returning")
            return
        }
        if (overlayView != null) {
            Log.d(TAG, "Overlay already shown, returning")
            return
        }

        isScreensaverShown = true
        val layout = FrameLayout(this)
        layout.setBackgroundColor(Color.BLACK)

        // Image or Video
        when (screensaverType) {
            "IMAGE" -> {
                screensaverImageFile?.takeIf { it.exists() }?.let {
                    Log.d(TAG, "Displaying image: ${it.path}")
                    val imageView = ImageView(this)
                    imageView.setImageBitmap(BitmapFactory.decodeFile(it.path))
                    imageView.scaleType = ImageView.ScaleType.FIT_CENTER
                    layout.addView(
                        imageView,
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                } ?: Log.d(TAG, "Image file not found")
            }
            "VIDEO" -> {
                screensaverVideoFile?.takeIf { it.exists() }?.let { file ->
                    Log.d(TAG, "Playing video: ${file.path}")
                    val videoView = VideoView(this)
                    videoView.setVideoPath(file.path)
                    videoView.setOnPreparedListener { mp ->
                        mp.isLooping = true

                        // Hitung scaling proporsional
                        val videoWidth = mp.videoWidth
                        val videoHeight = mp.videoHeight
                        layout.post {
                            val layoutWidth = layout.width
                            val layoutHeight = layout.height
                            val scaleX = layoutWidth.toFloat() / videoWidth
                            val scaleY = layoutHeight.toFloat() / videoHeight
                            val scale = minOf(scaleX, scaleY)

                            val lp = FrameLayout.LayoutParams(
                                (videoWidth * scale).toInt(),
                                (videoHeight * scale).toInt()
                            )
                            lp.gravity = Gravity.CENTER
                            videoView.layoutParams = lp

                            videoView.start()
                            Log.d(TAG, "Video started with scaling: $scale")
                        }
                    }
                    layout.addView(videoView)
                } ?: Log.d(TAG, "Video file not found")
            }
            "TEXT" -> {
                Log.d(TAG, "Displaying text: $screensaverText")
                val textView = TextView(this)
                textView.text = screensaverText ?: ""
                textView.setTextColor(Color.WHITE)
                textView.textSize = 24f
                textView.gravity = Gravity.CENTER
                layout.addView(
                    textView,
                    FrameLayout.LayoutParams.MATCH_PARENT,
                    FrameLayout.LayoutParams.MATCH_PARENT
                )
            }
            else -> Log.d(TAG, "Unknown screensaver type: $screensaverType")
        }

        layout.setOnTouchListener { _, event ->
            if (event.action == MotionEvent.ACTION_DOWN) {
                Log.d(TAG, "Overlay touched, resetting idle timer")
                resetIdleTimer()
                true
            } else false
        }

        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else
                WindowManager.LayoutParams.TYPE_SYSTEM_ALERT,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL,
            PixelFormat.TRANSLUCENT
        )
        params.gravity = Gravity.TOP or Gravity.START

        overlayView = layout
        windowManager?.addView(overlayView, params)
        Log.d(TAG, "Overlay added to window")

        // Immersive mode
        overlayView?.systemUiVisibility = (View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                or View.SYSTEM_UI_FLAG_FULLSCREEN
                or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                or View.SYSTEM_UI_FLAG_LAYOUT_STABLE)
    }

    private fun hideOverlay() {
        Log.d(TAG, "Hiding overlay")
        overlayView?.let { windowManager?.removeViewImmediate(it) }
        overlayView = null
        isScreensaverShown = false
    }
}
