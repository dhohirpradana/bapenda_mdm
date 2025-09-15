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
import android.media.MediaPlayer
import android.text.TextUtils

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
        
        // Early returns untuk validasi
        if (!isScreensaverEnabled) {
            Log.d(TAG, "Screensaver disabled, returning")
            return
        }
        
        if (overlayView != null) {
            Log.d(TAG, "Overlay already shown, returning")
            return
        }

        try {
            isScreensaverShown = true
            
            // Create base layout dengan optimized setup
            val layout = createBaseLayout()
            
            // Add content berdasarkan type
            val contentAdded = when (screensaverType) {
                "IMAGE" -> addImageContent(layout)
                "VIDEO" -> addVideoContent(layout)
                "TEXT" -> addTextContent(layout)
                else -> {
                    Log.w(TAG, "Unknown screensaver type: $screensaverType")
                    false
                }
            }
            
            if (!contentAdded) {
                Log.w(TAG, "Failed to add content, aborting overlay creation")
                isScreensaverShown = false
                return
            }
            
            // Setup touch handling
            setupTouchHandling(layout)
            
            // Show overlay dengan proper window params
            showOverlayWindow(layout)
            
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show overlay: ${e.message}", e)
            cleanup()
        }
    }

    /**
    * Membuat base layout dengan konfigurasi optimal
    */
    private fun createBaseLayout(): FrameLayout {
        return FrameLayout(this).apply {
            setBackgroundColor(Color.BLACK)
            keepScreenOn = true // Mencegah screen timeout saat screensaver aktif
        }
    }

    /**
    * Menambahkan konten gambar dengan optimasi memory
    */
    private fun addImageContent(layout: FrameLayout): Boolean {
        val imageFile = screensaverImageFile?.takeIf { it.exists() && it.length() > 0 }
        
        if (imageFile == null) {
            Log.d(TAG, "Image file not found or empty")
            return false
        }
        
        return try {
            Log.d(TAG, "Displaying image: ${imageFile.path}")
            
            // Optimized image loading dengan memory management
            val options = BitmapFactory.Options().apply {
                // Sample down untuk mencegah OOM
                inJustDecodeBounds = true
            }
            BitmapFactory.decodeFile(imageFile.path, options)
            
            // Calculate optimal sample size
            val displayMetrics = resources.displayMetrics
            val reqWidth = displayMetrics.widthPixels
            val reqHeight = displayMetrics.heightPixels
            
            options.apply {
                inSampleSize = calculateInSampleSize(this, reqWidth, reqHeight)
                inJustDecodeBounds = false
                inPreferredConfig = Bitmap.Config.RGB_565 // Use less memory
            }
            
            val bitmap = BitmapFactory.decodeFile(imageFile.path, options)
            
            if (bitmap != null) {
                val imageView = ImageView(this).apply {
                    setImageBitmap(bitmap)
                    scaleType = ImageView.ScaleType.FIT_CENTER
                    adjustViewBounds = true
                }
                
                layout.addView(
                    imageView,
                    FrameLayout.LayoutParams(
                        FrameLayout.LayoutParams.MATCH_PARENT,
                        FrameLayout.LayoutParams.MATCH_PARENT
                    )
                )
                
                // Store bitmap reference untuk cleanup nanti
                currentScreensaverBitmap = bitmap
                true
            } else {
                Log.e(TAG, "Failed to decode image bitmap")
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error loading image: ${e.message}", e)
            false
        }
    }

    /**
    * Menambahkan konten video dengan improved handling
    */
    private fun addVideoContent(layout: FrameLayout): Boolean {
        val videoFile = screensaverVideoFile?.takeIf { it.exists() && it.length() > 0 }
        
        if (videoFile == null) {
            Log.d(TAG, "Video file not found or empty")
            return false
        }
        
        return try {
            Log.d(TAG, "Playing video: ${videoFile.path}")
            
            val videoView = VideoView(this).apply {
                setVideoPath(videoFile.path)
                
                setOnPreparedListener { mediaPlayer ->
                    try {
                        mediaPlayer.isLooping = true
                        
                        // Optimized video scaling
                        setupVideoScaling(this, mediaPlayer, layout)
                        
                    } catch (e: Exception) {
                        Log.e(TAG, "Error in video prepared listener: ${e.message}", e)
                    }
                }
                
                setOnErrorListener { _, what, extra ->
                    Log.e(TAG, "Video playback error: what=$what, extra=$extra")
                    false // Return false to trigger onCompletion
                }
                
                setOnCompletionListener {
                    Log.d(TAG, "Video playback completed")
                    // Video akan loop otomatis karena isLooping = true
                }
            }
            
            layout.addView(videoView)
            currentVideoView = videoView
            true
            
        } catch (e: Exception) {
            Log.e(TAG, "Error setting up video: ${e.message}", e)
            false
        }
    }

    /**
    * Setup video scaling yang lebih efisien
    */
    private fun setupVideoScaling(videoView: VideoView, mediaPlayer: MediaPlayer, layout: FrameLayout) {
        val videoWidth = mediaPlayer.videoWidth
        val videoHeight = mediaPlayer.videoHeight
        
        if (videoWidth <= 0 || videoHeight <= 0) {
            Log.w(TAG, "Invalid video dimensions: ${videoWidth}x${videoHeight}")
            videoView.start()
            return
        }
        
        // Use ViewTreeObserver untuk mendapatkan layout dimensions
        layout.viewTreeObserver.addOnGlobalLayoutListener(object : ViewTreeObserver.OnGlobalLayoutListener {
            override fun onGlobalLayout() {
                layout.viewTreeObserver.removeOnGlobalLayoutListener(this)
                
                val layoutWidth = layout.width
                val layoutHeight = layout.height
                
                if (layoutWidth > 0 && layoutHeight > 0) {
                    val scaleX = layoutWidth.toFloat() / videoWidth
                    val scaleY = layoutHeight.toFloat() / videoHeight
                    val scale = minOf(scaleX, scaleY)
                    
                    val scaledWidth = (videoWidth * scale).toInt()
                    val scaledHeight = (videoHeight * scale).toInt()
                    
                    val layoutParams = FrameLayout.LayoutParams(scaledWidth, scaledHeight).apply {
                        gravity = Gravity.CENTER
                    }
                    
                    videoView.layoutParams = layoutParams
                    videoView.start()
                    
                    Log.d(TAG, "Video started with scaling: $scale (${scaledWidth}x${scaledHeight})")
                } else {
                    // Fallback jika layout dimensions tidak valid
                    videoView.start()
                    Log.d(TAG, "Video started without scaling (invalid layout dimensions)")
                }
            }
        })
    }

    /**
    * Menambahkan konten teks dengan better styling
    */
    private fun addTextContent(layout: FrameLayout): Boolean {
        val text = screensaverText?.takeIf { it.isNotBlank() }
        
        if (text == null) {
            Log.d(TAG, "Screensaver text is empty or null")
            return false
        }
        
        Log.d(TAG, "Displaying text: $text")
        
        val textView = TextView(this).apply {
            this.text = text
            setTextColor(Color.WHITE)
            textSize = 24f
            gravity = Gravity.CENTER
            typeface = Typeface.DEFAULT_BOLD
            
            // Add text shadow untuk better readability
            setShadowLayer(4f, 2f, 2f, Color.BLACK)
            
            // Enable anti-aliasing
            paint.isAntiAlias = true
            
            // Auto-resize text jika terlalu panjang
            maxLines = 10
            ellipsize = TextUtils.TruncateAt.END
        }
        
        layout.addView(
            textView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            ).apply {
                // Add padding untuk text
                leftMargin = 48
                rightMargin = 48
                topMargin = 48
                bottomMargin = 48
            }
        )
        
        return true
    }

    /**
    * Setup touch handling dengan debouncing
    */
    private fun setupTouchHandling(layout: FrameLayout) {
        var lastTouchTime = 0L
        val touchDebounceMs = 300L // Prevent rapid touches
        
        layout.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    val currentTime = System.currentTimeMillis()
                    if (currentTime - lastTouchTime > touchDebounceMs) {
                        Log.d(TAG, "Overlay touched, resetting idle timer")
                        resetIdleTimer()
                        lastTouchTime = currentTime
                    }
                    true
                }
                else -> false
            }
        }
    }

    /**
    * Show overlay window dengan optimized parameters
    */
    private fun showOverlayWindow(layout: FrameLayout) {
        val windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager
        
        val params = createOptimizedWindowParams()
        
        overlayView = layout
        windowManager.addView(overlayView, params)
        
        // Setup immersive mode dengan delay untuk stability
        layout.post {
            setupImmersiveMode(layout)
        }
        
        Log.d(TAG, "Overlay added to window successfully")
    }

    /**
    * Membuat window parameters yang optimal
    */
    private fun createOptimizedWindowParams(): WindowManager.LayoutParams {
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_SYSTEM_ALERT
        }
        
        return WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.MATCH_PARENT,
            type,
            WindowManager.LayoutParams.FLAG_FULLSCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                    WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                    WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED, // Enable hardware acceleration
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            // Optimize for performance
            format = PixelFormat.RGBA_8888
        }
    }

    /**
    * Setup immersive mode yang stabil
    */
    private fun setupImmersiveMode(view: View) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Use new Window Insets API for Android 11+
            view.windowInsetsController?.let { controller ->
                controller.hide(WindowInsets.Type.systemBars())
                controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            // Use legacy flags for older versions
            @Suppress("DEPRECATION")
            view.systemUiVisibility = (
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE
            )
        }
    }

    /**
    * Menghitung sample size optimal untuk bitmap
    */
    private fun calculateInSampleSize(options: BitmapFactory.Options, reqWidth: Int, reqHeight: Int): Int {
        val (height: Int, width: Int) = options.run { outHeight to outWidth }
        var inSampleSize = 1

        if (height > reqHeight || width > reqWidth) {
            val halfHeight: Int = height / 2
            val halfWidth: Int = width / 2

            while (halfHeight / inSampleSize >= reqHeight && halfWidth / inSampleSize >= reqWidth) {
                inSampleSize *= 2
            }
        }

        return inSampleSize
    }

    /**
    * Cleanup resources saat error atau destroy
    */
    private fun cleanup() {
        isScreensaverShown = false
        
        // Cleanup bitmap
        currentScreensaverBitmap?.let {
            if (!it.isRecycled) {
                it.recycle()
            }
            currentScreensaverBitmap = null
        }
        
        // Cleanup video
        currentVideoView?.let {
            it.stopPlayback()
            currentVideoView = null
        }
        
        // Remove overlay
        overlayView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (e: Exception) {
                Log.e(TAG, "Error removing overlay: ${e.message}", e)
            }
            overlayView = null
        }
    }

    // Additional properties untuk resource management
    private var currentScreensaverBitmap: Bitmap? = null
    private var currentVideoView: VideoView? = null

    private fun hideOverlay() {
        Log.d(TAG, "Hiding overlay")
        overlayView?.let { windowManager?.removeViewImmediate(it) }
        overlayView = null
        isScreensaverShown = false
    }
}
