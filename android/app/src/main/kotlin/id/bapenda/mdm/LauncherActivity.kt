package id.bapenda.mdm

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class LauncherActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Redirect ke MainActivity
        startActivity(Intent(this, MainActivity::class.java))
        finish()
    }
}
