package com.blackface.bfstickytask

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cài APK bản mới — xem ApkInstaller.kt.
        ApkInstaller.register(flutterEngine.dartExecutor.binaryMessenger, applicationContext)
    }
}
