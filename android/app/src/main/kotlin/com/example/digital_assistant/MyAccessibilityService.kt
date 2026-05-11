package com.example.digital_assistant
import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.TakeScreenshotCallback
import android.accessibilityservice.AccessibilityService.ScreenshotResult
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.util.Log
import android.view.Display
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

class MyAccessibilityService : AccessibilityService() {

    companion object {
        var instance: MyAccessibilityService? = null
    }

    // 🎯 CRITICAL: Stores the exact field found by findNextEmptyField.
    // When the user taps the mic/camera in the overlay, Android shifts input
    // focus to the overlay window. This saved reference lets injectText()
    // always inject into the CORRECT field, not just the first one on screen.
    private var lastTargetField: AccessibilityNodeInfo? = null

    override fun onServiceConnected() {
        instance = this
        Log.d("Accessibility", "Service Connected")
    }



    override fun onInterrupt() {
        instance = null
    }
    fun getCurrentApp(): String? {
        val rootNode = rootInActiveWindow ?: return null
        return rootNode.packageName?.toString()
    }

    // --- FEATURE 1: GET ALL SCREEN TEXT ---
    fun getScreenText(): String {
        try {
            val rootNode = rootInActiveWindow ?: return ""
            val sb = StringBuilder()
            val displayMetrics = resources.displayMetrics
            readNode(rootNode, sb, displayMetrics.widthPixels, displayMetrics.heightPixels)
            return sb.toString()
        } catch (e: Exception) { return "" }
    }

    private fun readNode(node: AccessibilityNodeInfo, sb: StringBuilder, width: Int, height: Int) {
        if (!node.isVisibleToUser) return
        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.left > width || rect.top > height || rect.right < 0 || rect.bottom < 0) return 
        if (node.text != null && node.text.isNotEmpty()) {
            sb.append(node.text.toString()).append("\n")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            readNode(child, sb, width, height)
        }
    }

    // --- FEATURE 2: SCREENSHOT ---
    fun takeScreenshot(callback: (String?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(Display.DEFAULT_DISPLAY, applicationContext.mainExecutor, object : TakeScreenshotCallback {
                override fun onSuccess(res: ScreenshotResult) {
                    val hardwareBitmap = Bitmap.wrapHardwareBuffer(res.hardwareBuffer, res.colorSpace)
                    val softwareBitmap = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, true)
                    res.hardwareBuffer.close()
                    softwareBitmap?.let { callback(saveBitmapToFile(it)) } ?: callback(null)
                }
                override fun onFailure(code: Int) { callback(null) }
            })
        } else callback(null)
    }

    private fun saveBitmapToFile(bitmap: Bitmap): String? {
        val file = File(cacheDir, "screen_capture.png")
        return try {
            val out = FileOutputStream(file)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.close()
            file.absolutePath
        } catch (e: IOException) { null }
    }

    // --- FEATURE 3: SMART FIELD DETECTION ---
    // Returns the next field that needs to be filled.
    // If all fields are filled → returns "" → Flutter falls back to translation.
    fun getFormFields(): String {
        val rootNode = rootInActiveWindow ?: return ""
        val focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)

        if (focusedNode != null && focusedNode.isEditable) {
            val id = focusedNode.viewIdResourceName ?: ""
            // Skip browser address bars and search boxes
            if (id.contains("url_bar") || id.contains("search_box") || id.contains("omnibox")) {
                // On a browser/search screen — return empty to trigger translation
                return ""
            }

            val currentText = focusedNode.text?.toString() ?: ""
            if (currentText.isEmpty()) {
                // ✅ CASE 1: Focused field is EMPTY → this is what needs to be filled
                val prefix = if (focusedNode.isPassword) "[PASSWORD]" else "[FIELD]"
                return "$prefix: ${focusedNode.hintText ?: "Field"}\n"
            } else {
                // ✅ CASE 2: Focused field is ALREADY FILLED → skip to next empty field
                return findNextEmptyField() ?: ""
            }
        }

        // ✅ CASE 3: No focused field → find first empty field in form
        return findNextEmptyField() ?: ""
    }

    private fun findEditableNodes(node: AccessibilityNodeInfo, sb: StringBuilder) {
        if (!node.isVisibleToUser) return
        val id = node.viewIdResourceName ?: ""
        if (id.contains("url_bar") || id.contains("search_box")) return
        if (node.isEditable) {
            // 🛡️ Distinguish password vs normal field
            val prefix = if (node.isPassword) "[PASSWORD]" else "[FIELD]"
            sb.append("$prefix: ${node.hintText ?: node.text ?: "Field"}\n")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            findEditableNodes(child, sb)
        }
    }

    // --- FEATURE: FORGOT PASSWORD CLICKER ---
    fun clickForgotPassword(): Boolean {
        val rootNode = rootInActiveWindow ?: return false
        rootNode.refresh()

        val flatList = mutableListOf<AccessibilityNodeInfo>()
        flattenTree(rootNode, flatList)

        for (node in flatList) {
            if (!node.isVisibleToUser) continue
            val text = (node.text?.toString() ?: "").lowercase()
            val contentDesc = (node.contentDescription?.toString() ?: "").lowercase()
            val identifier = "$text $contentDesc"

            if (identifier.contains("forgot") || identifier.contains("മറന്നോ") || 
                identifier.contains("reset") || identifier.contains("trouble") ||
                identifier.contains("forget")) {
                
                // Ensure it is actually clickable or has a clickable parent
                if (node.isClickable) {
                    node.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
                    node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    return true
                } else {
                    var ancestor = node.parent
                    var depth = 0
                    while (ancestor != null && depth < 3) {
                        if (ancestor.isClickable) {
                            ancestor.performAction(AccessibilityNodeInfo.ACTION_ACCESSIBILITY_FOCUS)
                            ancestor.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            return true
                        }
                        ancestor = ancestor.parent
                        depth++
                    }
                }
            }
        }
        return false
    }

    // =======================================================
    // --- FEATURE 4: UNIVERSAL AUTO-FILL ENGINE (NEW) ---
    // =======================================================
    // 🛡️ UPDATED: Uses a persistent handler to survive app switching
    fun autoFillAllFields(dataMap: Map<String, String>) {
        Log.d("Assistant", "🚀 Persistence Start: ${dataMap.keys}")
        val mainHandler = Handler(Looper.getMainLooper())
        
        val runnable = object : Runnable {
            var retryCount = 0
            override fun run() {
                val rootNode = rootInActiveWindow
                // 🛡️ REFRESH IS KEY: Forces Android to see the browser behind the app
                rootNode?.refresh() 
                
                val filledSomething = if (rootNode != null) fillNodesRecursively(rootNode, dataMap) else false
                
                // 🛡️ INCREASE RETRY: Give it 10 tries (approx 6 seconds) to find the form
                if (!filledSomething && retryCount < 10) {
                    retryCount++
                    mainHandler.postDelayed(this, 600)
                }
            }
        }
        mainHandler.post(runnable)
    }

    private fun fillNodesRecursively(rootNode: AccessibilityNodeInfo, dataMap: Map<String, String>): Boolean {
        var anyFilled = false
        rootNode.refresh()

        val flatList = mutableListOf<AccessibilityNodeInfo>()
        flattenTree(rootNode, flatList)

        for (i in 0 until flatList.size) {
            val node = flatList[i]
            if (!node.isVisibleToUser) continue

            val hint = (node.hintText?.toString() ?: "").lowercase()
            val contentDesc = (node.contentDescription?.toString() ?: "").lowercase()
            val text = (node.text?.toString() ?: "").lowercase()
            val identifier = "$hint $contentDesc $text".lowercase()

            for ((key, value) in dataMap) {
                if (value.isEmpty() || value == "null") continue
                val targetVal = value.lowercase()
                
                // 🛡️ UNIVERSAL MATCHING
                val isMatch = when (key) {
                    // 🛡️ NAME: Prevents Account Number overwrite
                    "full name" -> (identifier.contains("name") || identifier.contains("holder")) &&
                                   !identifier.contains("number") && !identifier.contains("no") &&
                                   !identifier.contains("user") && !identifier.contains("brand") &&
                                   !identifier.contains("bank") && !identifier.contains("branch")

                    // 🛡️ ACCOUNT NUMBER: Strict digits check
                    "account number" -> identifier.contains("account") && (identifier.contains("number") || identifier.contains("no")) &&
                                        !identifier.contains("name") && !identifier.contains("holder")

                    // 🛡️ GENDER & IDENTITY
                    "gender" -> identifier.contains("gender") || identifier.contains("sex") ||
                                identifier.contains("male") || identifier.contains("female")
                    "id number" -> (identifier.contains("id") || identifier.contains("aadhaar") ||
                                    identifier.contains("aadhar") || identifier.contains("adhaar") ||
                                    identifier.contains("uid")) && !identifier.contains("mobile")

                    // 🛡️ DOB: Comprehensive matching for ALL common form field labels
                    "dob" -> identifier.contains("dob") ||
                             identifier.contains("d.o.b") ||
                             identifier.contains("date of birth") ||
                             identifier.contains("birth date") ||
                             identifier.contains("birthdate") ||
                             identifier.contains("birthday") ||
                             identifier.contains("birth year") ||
                             identifier.contains("year of birth") ||
                             (identifier.contains("date") && identifier.contains("birth")) ||
                             // Match standalone 'date' ONLY if no other date context overrides it
                             (identifier.contains("date") &&
                              !identifier.contains("update") &&
                              !identifier.contains("creat") &&
                              !identifier.contains("issue") &&
                              !identifier.contains("expir") &&
                              !identifier.contains("valid") &&
                              !identifier.contains("from") &&
                              !identifier.contains("to"))

                    // 🛡️ BANK DETAILS
                    "bank name" -> identifier.contains("bank") && (identifier.contains("name") || !identifier.contains("account"))
                    "ifsc" -> identifier.contains("ifsc") || identifier.contains("ifsc code") ||
                               (identifier.contains("code") && !identifier.contains("pin"))
                    "branch name" -> identifier.contains("branch") || identifier.contains("office")

                    // 🛡️ ADDRESS SPLIT
                    "pincode" -> identifier.contains("pincode") || identifier.contains("pin code") ||
                                  identifier.contains("postal") || identifier.contains("zip")
                    "full address" -> identifier.contains("address") && !identifier.contains("house") && !identifier.contains("street")
                    "house name" -> identifier.contains("house") || identifier.contains("building") || identifier.contains("home")
                    "street" -> identifier.contains("street") || identifier.contains("road") || identifier.contains("lane")
                    "place" -> identifier.contains("place") || identifier.contains("city") || identifier.contains("town") || identifier.contains("location")
                    "district" -> identifier.contains("district") || identifier.contains("dist")
                    "state" -> identifier.contains("state")

                    // 🛡️ UTILITIES
                    "consumer number" -> identifier.contains("consumer") || identifier.contains("customer") || identifier.contains("con no")

                    else -> identifier.contains(key.lowercase())
                }

                if (isMatch) {
                    // 🎯 STEP 1: If it's an editable box, type into it.
                    if (node.isEditable) {
                        injectToNode(node, value, key)
                        anyFilled = true
                    }
                    // 🎯 STEP 2: If it's a radio/checkbox that matches the value label, click it.
                    else if (identifier.contains(targetVal)) {
                        if (node.isClickable || node.isCheckable) {
                            node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                            anyFilled = true
                        } else {
                            var ancestor = node.parent
                            var found = false
                            var depth = 0
                            while (ancestor != null && depth < 4) {
                                if (ancestor.isClickable || ancestor.isCheckable) {
                                    ancestor.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                                    found = true
                                    anyFilled = true
                                    break
                                }
                                ancestor = ancestor.parent
                                depth++
                            }
                            if (!found) {
                                var inputNode: AccessibilityNodeInfo? = null
                                for (j in i + 1 until flatList.size) {
                                    val candidate = flatList[j]
                                    if (candidate.isEditable && candidate.isVisibleToUser) {
                                        val currentText = candidate.text?.toString() ?: ""
                                        if (currentText.isEmpty()) {
                                            inputNode = candidate
                                            break
                                        }
                                    }
                                }
                                if (inputNode != null) {
                                    injectToNode(inputNode, value, key)
                                    anyFilled = true
                                }
                            }
                        }
                    }
                    // 🎯 STEP 3: Label match — search deep for the associated editable field
                    else {
                        var inputNode: AccessibilityNodeInfo? = null
                        for (j in i + 1 until flatList.size) {
                            val candidate = flatList[j]
                            if (candidate.isEditable && candidate.isVisibleToUser) {
                                val currentText = candidate.text?.toString() ?: ""
                                if (currentText.isEmpty()) {
                                    inputNode = candidate
                                    break
                                }
                            }
                        }
                        if (inputNode != null) {
                            injectToNode(inputNode, value, key)
                            anyFilled = true
                        }
                    }
                }
            }
        }
        return anyFilled
    }

    private fun flattenTree(node: AccessibilityNodeInfo?, list: MutableList<AccessibilityNodeInfo>) {
        if (node == null) return
        list.add(node)
        for (i in 0 until node.childCount) {
            flattenTree(node.getChild(i), list)
        }
    }

    private fun injectToNode(node: AccessibilityNodeInfo, value: String, key: String) {
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)

        val clearArgs = Bundle()
        clearArgs.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, clearArgs)

        try { Thread.sleep(100) } catch (e: Exception) {}

        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value)

        var success = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)

        if (!success) {
            val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("label", value))
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        }
    }
    // --- FEATURE 5: VOICE TEXT INJECTION ---
    // Injects text into the saved target field from findNextEmptyField().
    // This is necessary because the overlay mic button steals input focus
    // away from the form field while the user is speaking.
    fun injectText(textToInject: String): Boolean {
        try {
            val rootNode = rootInActiveWindow ?: return false
            rootNode.refresh()

            // 🎯 PRIORITY 1: Use the SAVED field from findNextEmptyField()
            // This is the field we identified as the target BEFORE the mic was tapped.
            val saved = lastTargetField
            if (saved != null) {
                saved.refresh()
                if (saved.isVisibleToUser && saved.isEditable) {
                    saved.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    saved.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    Thread.sleep(150)
                    val args = Bundle()
                    args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToInject)
                    val success = saved.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    lastTargetField = null // Clear after successful use
                    if (success) return true
                    // Fallback: clipboard paste on same field
                    val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    clipboard.setPrimaryClip(android.content.ClipData.newPlainText("voice", textToInject))
                    val pasted = saved.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                    if (pasted) return true
                }
                lastTargetField = null
            }

            // 🛡️ PRIORITY 2: Currently focused field (if saved field unavailable)
            val focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focusedNode != null && focusedNode.isEditable && focusedNode.isVisibleToUser) {
                val id = focusedNode.viewIdResourceName ?: ""
                if (!id.contains("url_bar") && !id.contains("search_box") && !id.contains("omnibox")) {
                    focusedNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    Thread.sleep(150)
                    val args = Bundle()
                    args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToInject)
                    val success = focusedNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    if (success) return true
                    val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
                    clipboard.setPrimaryClip(android.content.ClipData.newPlainText("voice", textToInject))
                    return focusedNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                }
            }

            // 🛡️ PRIORITY 3: Fallback - first visible empty form field
            val targetNode = findVisibleFormBox(rootNode)
            if (targetNode != null) {
                targetNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                targetNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                Thread.sleep(200)
                val arguments = Bundle()
                arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToInject)
                var success = targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                if (!success) success = targetNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                return success
            }
            return false
        } catch (e: Exception) { return false }
    }

    private fun findVisibleFormBox(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val id = node.viewIdResourceName ?: ""
        if (id.contains("url_bar") || id.contains("search_box") || id.contains("omnibox")) return null
        if (node.isEditable && node.isVisibleToUser && !node.isPassword) return node
        for (i in 0 until node.childCount) {
            val result = findVisibleFormBox(node.getChild(i) ?: continue)
            if (result != null) return result
        }
        return null
    }
    // 🛡️ THE MISSING FUNCTION: Searches for the next blank box, with auto-scroll!
    fun findNextEmptyField(): String? {
        var rootNode = rootInActiveWindow ?: return null
        rootNode.refresh()
        var result = searchForEmpty(rootNode)
        
        // 🛡️ If no empty fields found, try scrolling down to see off-screen fields!
        if (result == null) {
            val scrollable = findScrollableNode(rootNode)
            if (scrollable != null) {
                Log.d("Assistant", "No empty fields visible. Scrolling forward...")
                scrollable.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                try { Thread.sleep(800) } catch (e: Exception) {} // Wait for scroll animation
                
                rootNode = rootInActiveWindow ?: return null
                rootNode.refresh()
                result = searchForEmpty(rootNode)
            }
        }
        return result
    }

    private fun findScrollableNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isScrollable) return node
        for (i in 0 until node.childCount) {
            val res = findScrollableNode(node.getChild(i) ?: continue)
            if (res != null) return res
        }
        return null
    }

    private fun searchForEmpty(node: AccessibilityNodeInfo): String? {
        // Look for editable fields that are visible and HAVE NO TEXT
        if (node.isEditable && node.isVisibleToUser) {
            val currentText = node.text?.toString() ?: ""
            val id = node.viewIdResourceName ?: ""
            
            // Skip browser bars and fields that already have data
            if (!id.contains("url_bar") && !id.contains("search_box") && currentText.isEmpty()) {
                val hint = node.hintText?.toString() ?: "Field"
                val prefix = if (node.isPassword) "[PASSWORD]" else "[FIELD]"
                
                // 🎯 SAVE the exact node so injectText() can find it later
                // even after the overlay mic steals input focus away.
                lastTargetField = node
                
                // Focus the field so the cursor jumps visually
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                return "$prefix: $hint"
            }
        }
        for (i in 0 until node.childCount) {
            val result = searchForEmpty(node.getChild(i) ?: continue)
            if (result != null) return result
        }
        return null
    }

    // --- OTP WATCH: Listen for notifications that contain OTP digits ---
    private var otpWatchActive = false
    fun startWatchingForOtp() {
        otpWatchActive = true
        Log.d("Assistant", "OTP watch started")
        // The onAccessibilityEvent below handles the actual OTP capture.
        // This function just flips the flag so we process OTP events.
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        if (!otpWatchActive) return
        if (event == null) return

        // Capture notification banners for OTP
        if (event.eventType == AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED ||
            event.eventType == AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED) {

            val text = event.text.joinToString(" ")
            // Look for 4-8 digit OTP in the notification text
            val otpRegex = Regex("\\b(\\d{4,8})\\b")
            val match = otpRegex.find(text)
            if (match != null) {
                val otp = match.value
                Log.d("Assistant", "OTP detected: $otp")
                otpWatchActive = false // Stop watching after we find it

                Handler(Looper.getMainLooper()).postDelayed({
                    val rootNode = rootInActiveWindow ?: return@postDelayed
                    rootNode.refresh()
                    val target = findVisibleFormBox(rootNode)
                    if (target != null) {
                        injectToNode(target, otp, "otp")
                        // Notify Flutter bubble that OTP was filled
                        try {
                            val channel = MethodChannel(
                                com.example.digital_assistant.MainActivityRef.binaryMessenger!!,
                                "com.example.digital_assistant/accessibility"
                            )
                        } catch (e: Exception) {
                            Log.d("Assistant", "OTP filled, notify via shareData not available here")
                        }
                    }
                }, 500)
            }
        }
    }
}