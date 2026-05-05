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
        // 🛡️ Ensure we are looking at a fresh tree
        node.refresh()

        if (node.isVisibleToUser) {
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
                                   !identifier.contains("number") && !identifier.contains("no")
                    
                    // 🛡️ ACCOUNT NUMBER: Strict digits check
                    "account number" -> identifier.contains("account") && (identifier.contains("number") || identifier.contains("no")) && 
                                        !identifier.contains("name") && !identifier.contains("holder")
                    
                    // 🛡️ GENDER & IDENTITY
                    "gender" -> identifier.contains("gender") || identifier.contains("sex") || 
                                identifier.contains("male") || identifier.contains("female")
                    "id number" -> (identifier.contains("id") || identifier.contains("aadhaar") || identifier.contains("aadhar")) && !identifier.contains("mobile")
                    "dob" -> identifier.contains("dob") || identifier.contains("birth") || identifier.contains("date")

                    // 🛡️ BANK DETAILS
                    "ifsc" -> identifier.contains("ifsc") || identifier.contains("code")
                    "branch name" -> identifier.contains("branch") || identifier.contains("office")
                    
                    // 🛡️ ADDRESS SPLIT (REPLACED & COMPLETE)
                    "pincode" -> identifier.contains("pincode") || identifier.contains("pin") || identifier.contains("zip")
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
                    // 🎯 STEP 1: If it's a box, type.
                    if (node.isEditable) {
                        injectToNode(node, value, key)
                        anyFilled = true
                    } 
                    // 🎯 STEP 2: If it's a radio button (Gender), click.
                    else if (identifier.contains(targetVal) && (node.isClickable || node.isCheckable)) {
                        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        anyFilled = true
                    }
                    // 🎯 STEP 3: If it's just a label, find the box next to it.
                    else {
                        val inputNode = findNearestInput(node)
                        if (inputNode != null) {
                            injectToNode(inputNode, value, key)
                            anyFilled = true
                        }
                    }
                }
            }
        }

        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            if (fillNodesRecursively(child, dataMap)) anyFilled = true
        }
        return anyFilled
    }
    private fun injectToNode(node: AccessibilityNodeInfo, value: String, key: String) {
        node.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        node.performAction(AccessibilityNodeInfo.ACTION_CLICK)

        // 🛡️ EMERGENCY FIX: Clear the field first so data doesn't mix
        val clearArgs = Bundle()
        clearArgs.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "")
        node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, clearArgs)

        try { Thread.sleep(100) } catch (e: Exception) {}

        val args = Bundle()
        args.putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, value)

        var success = node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)

        // 🔥 FALLBACK: Paste works where SetText is blocked
        if (!success) {
            val clipboard = getSystemService(CLIPBOARD_SERVICE) as android.content.ClipboardManager
            clipboard.setPrimaryClip(android.content.ClipData.newPlainText("label", value))
            node.performAction(AccessibilityNodeInfo.ACTION_PASTE)
        }
    }

    private fun findNearestInput(startNode: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        val parent = startNode.parent ?: return null
        for (i in 0 until parent.childCount) {
            val sibling = parent.getChild(i) ?: continue
            if (sibling.isEditable) return sibling
        }
        val grandParent = parent.parent ?: return null
        for (i in 0 until grandParent.childCount) {
            val cousin = grandParent.getChild(i) ?: continue
            if (cousin.isEditable) return cousin
            for (j in 0 until cousin.childCount) {
                val subCousin = cousin.getChild(j) ?: continue
                if (subCousin.isEditable) return subCousin
            }
        }
        return null
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