package com.example.digital_assistant

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.digital_assistant/accessibility"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            val service = MyAccessibilityService.instance
            
            if (service == null) {
                result.error("SERVICE_OFF", "Accessibility Service is not running", null)
                return@setMethodCallHandler
            }

            if (call.method == "getScreenText") {
                // Feature 1: Get Text Code
                val text = service.getScreenText()
                result.success(text)
            } 
            else if (call.method == "takeScreenshot") {
                // Feature 2: Take Screenshot
                service.takeScreenshot { path ->
                    if (path != null) result.success(path)
                    else result.error("ERROR", "Screenshot failed", null)
                }
            } 
            else {
                result.notImplemented()
            }
        }
    }
}