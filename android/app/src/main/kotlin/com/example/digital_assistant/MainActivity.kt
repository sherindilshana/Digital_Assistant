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

            // --- TRANSLATION & OCR FEATURES ---
            if (call.method == "getScreenText") {
                val text = service.getScreenText()
                result.success(text)
            } 
            else if (call.method == "takeScreenshot") {
                service.takeScreenshot { path ->
                    if (path != null) result.success(path)
                    else result.error("ERROR", "Screenshot failed", null)
                }
            }
            else if (call.method == "getCurrentApp") {
                val app = service.getCurrentApp()
                result.success(app)
            } 
            // --- FORM ASSISTANCE FEATURES ---
            else if (call.method == "getFormFields") {
                val text = service.getFormFields()
                result.success(text)
            }
            else if (call.method == "injectText") {
                val textToInject = call.argument<String>("text") ?: ""
                val success = service.injectText(textToInject)
                if (success) {
                    result.success("Injected Successfully")
                } else {
                    result.error("ERROR", "Could not inject text.", null)
                }
            }
            // 🛡️ THE NEW AUTO-FILL ENGINE CONNECTION
            else if (call.method == "autoFillAllFields") {
                val dataMap = call.argument<Map<String, String>>("data_map") ?: emptyMap()
                if (dataMap.isNotEmpty()) {
                    service.autoFillAllFields(dataMap)
                    result.success("Auto-fill engine triggered")
                } else {
                    result.error("EMPTY_DATA", "No data provided for auto-fill", null)
                }
            }
            // 🛡️ NEW: THE AUTO-DETECTION CONNECTION
            else if (call.method == "findNextEmptyField") {
                val nextFieldHint = service.findNextEmptyField()
                // This returns the hint of the first empty box it finds (e.g., "Mobile Number")
                result.success(nextFieldHint)
            }
            else {
                result.notImplemented()
            }
        }
    }
}