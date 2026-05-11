package com.example.digital_assistant

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.accounts.AccountManager
import android.app.Activity

// 🛡️ Global reference so AccessibilityService can reach the Flutter messenger
object MainActivityRef {
    var binaryMessenger: BinaryMessenger? = null
}

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.digital_assistant/accessibility"
    private var emailResult: io.flutter.plugin.common.MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Store messenger for AccessibilityService OTP channel
        MainActivityRef.binaryMessenger = flutterEngine.dartExecutor.binaryMessenger

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
                result.success(nextFieldHint)
            }
            // 🛡️ CRITICAL FIX: Move to back (keeps isolate port alive!)
            else if (call.method == "moveTaskToBack") {
                val moved = moveTaskToBack(true)
                result.success(moved)
            }
            // 📧 EMAIL POPUP: Native Android account picker
            else if (call.method == "showEmailPicker") {
                try {
                    val intent = AccountManager.newChooseAccountIntent(
                        null, null, arrayOf("com.google"), null, null, null, null
                    )
                    emailResult = result
                    startActivityForResult(intent, 1001)
                } catch (e: Exception) {
                    result.error("ERROR", e.message, null)
                }
            }
            // ⏳ OTP WATCH: Kotlin registers to listen for SMS (via NotificationListenerService or broadcast)
            else if (call.method == "startOtpWatch") {
                // The actual OTP capture is handled by the AccessibilityService
                // monitoring notifications. Here we just acknowledge.
                service.startWatchingForOtp()
                result.success("OTP watch started")
            }
            // 🛡️ NEW: FORGOT PASSWORD CLICKER
            else if (call.method == "clickForgotPassword") {
                val success = service.clickForgotPassword()
                result.success(success)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == 1001) {
            if (resultCode == Activity.RESULT_OK) {
                val email = data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME)
                if (email != null && email.isNotEmpty()) {
                    emailResult?.success(email)
                } else {
                    emailResult?.error("NO_EMAIL", "User cancelled or no email selected", null)
                }
            } else {
                emailResult?.error("CANCELLED", "User cancelled email picker", null)
            }
            emailResult = null
        } else {
            super.onActivityResult(requestCode, resultCode, data)
        }
    }
}