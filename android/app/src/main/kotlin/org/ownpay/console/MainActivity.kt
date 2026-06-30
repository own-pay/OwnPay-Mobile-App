package org.ownpay.console

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Expose native SMS capture (method + event channels) to Dart.
        SmsBridge.register(flutterEngine.dartExecutor.binaryMessenger, this)
    }
}
