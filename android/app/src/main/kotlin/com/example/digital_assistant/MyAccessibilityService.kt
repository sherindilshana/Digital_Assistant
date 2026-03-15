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

class MyAccessibilityService : AccessibilityService() {

    companion object {
        var instance: MyAccessibilityService? = null
    }

    override fun onServiceConnected() {
        instance = this
        Log.d("Accessibility", "Service Connected")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}

    override fun onInterrupt() {
        instance = null
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

    // --- FEATURE 3: SMART FIELD DETECTION (Search Bar Filter) ---
    fun getFormFields(): String {
        val rootNode = rootInActiveWindow ?: return ""
        val focusedNode = rootNode.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        
        if (focusedNode != null && focusedNode.isEditable) {
            val id = focusedNode.viewIdResourceName ?: ""
            if (id.contains("url_bar") || id.contains("search_box") || id.contains("omnibox")) {
                val sb = StringBuilder()
                findEditableNodes(rootNode, sb)
                return sb.toString()
            }
            return "[FIELD]: ${focusedNode.hintText ?: focusedNode.text ?: "Field"}\n"
        }
        val sb = StringBuilder()
        findEditableNodes(rootNode, sb)
        return sb.toString()
    }

    private fun findEditableNodes(node: AccessibilityNodeInfo, sb: StringBuilder) {
        if (!node.isVisibleToUser) return
        val id = node.viewIdResourceName ?: ""
        if (id.contains("url_bar") || id.contains("search_box")) return
        if (node.isEditable && !node.isPassword) {
            sb.append("[FIELD]: ${node.hintText ?: node.text ?: "Field"}\n")
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            findEditableNodes(child, sb)
        }
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

    private fun fillNodesRecursively(node: AccessibilityNodeInfo, dataMap: Map<String, String>): Boolean {
        var anyFilled = false
        if (node.isEditable && node.isVisibleToUser) {
            val hint = (node.hintText?.toString() ?: "").lowercase()
            val contentDesc = (node.contentDescription?.toString() ?: "").lowercase()
            val currentText = (node.text?.toString() ?: "").lowercase()
            val identifier = "$hint $contentDesc $currentText".replace("required question", "").replace("*", "").trim()

            for ((key, value) in dataMap) {
                if (value.isEmpty() || value == "null") continue
                
                val isMatch = when (key) {
                    "full name" -> identifier.contains("name")
                    "dob" -> identifier.contains("dob") || identifier.contains("birth")
                    "gender" -> identifier.contains("gender") || identifier.contains("sex")
                    "id number" -> identifier.contains("id") || identifier.contains("aadhaar") || identifier.contains("pan")
                    else -> identifier.contains(key)
                }

                if (isMatch) {
                    Log.d("Assistant", "🔥 INJECTING: $key -> $value")
                    node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                    node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    
                    // Small sleep to let the browser input connection open
                    Thread.sleep(150) 
                    
                    val args = Bundle()
                    args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value)
                    val success = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    
                    if (!success) { node.performAction(AccessibilityNodeInfo.ACTION_PASTE) }
                    anyFilled = true
                    break
                }
            }
        }
        for (i in 0 until node.childCount) {
            if (fillNodesRecursively(node.getChild(i) ?: continue, dataMap)) anyFilled = true
        }
        return anyFilled
    }
    // --- FEATURE 5: SINGLE INJECTION FALLBACK ---
    fun injectText(textToInject: String): Boolean {
        try {
            val rootNode = rootInActiveWindow ?: return false
            rootNode.refresh()
            val targetNode = findVisibleFormBox(rootNode)
            
            if (targetNode != null) {
                targetNode.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                targetNode.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                
                Thread.sleep(200)

                val arguments = Bundle()
                arguments.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, textToInject)
                
                var success = targetNode.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, arguments)
                if (!success) {
                    success = targetNode.performAction(AccessibilityNodeInfo.ACTION_PASTE)
                }
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
    // 🛡️ THE MISSING FUNCTION: Searches for the next blank box
    fun findNextEmptyField(): String? {
        val rootNode = rootInActiveWindow ?: return null
        rootNode.refresh()
        return searchForEmpty(rootNode)
    }

    private fun searchForEmpty(node: AccessibilityNodeInfo): String? {
        // Look for editable fields that are visible and HAVE NO TEXT
        if (node.isEditable && node.isVisibleToUser) {
            val currentText = node.text?.toString() ?: ""
            val id = node.viewIdResourceName ?: ""
            
            // Skip browser bars and fields that already have data
            if (!id.contains("url_bar") && !id.contains("search_box") && currentText.isEmpty()) {
                val hint = node.hintText?.toString() ?: "Field"
                
                // Focus the field so the user sees the cursor jump
                node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
                return hint
            }
        }
        for (i in 0 until node.childCount) {
            val result = searchForEmpty(node.getChild(i) ?: continue)
            if (result != null) return result
        }
        return null
    }
}