package com.example.digital_assistant

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityService.TakeScreenshotCallback
import android.accessibilityservice.AccessibilityService.ScreenshotResult
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Build
import android.util.Log
import android.view.Display
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

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

    fun getScreenText(): String {
        try {
            val rootNode = rootInActiveWindow ?: return ""
            val sb = StringBuilder()
            
            // Get screen dimensions to filter "Off-Screen" items
            val displayMetrics = resources.displayMetrics
            val screenWidth = displayMetrics.widthPixels
            val screenHeight = displayMetrics.heightPixels
            
            readNode(rootNode, sb, screenWidth, screenHeight)
            return sb.toString()
        } catch (e: Exception) {
            return ""
        }
    }

    private fun readNode(node: AccessibilityNodeInfo, sb: StringBuilder, width: Int, height: Int) {
        // 1. Ask Android: Is this visible to the user?
        if (!node.isVisibleToUser) return

        // 2. Double Check: Is it inside the screen boundaries?
        val rect = Rect()
        node.getBoundsInScreen(rect)
        if (rect.left > width || rect.top > height || rect.right < 0 || rect.bottom < 0) {
            return // It's off-screen (Ghost App), skip it.
        }

        if (node.text != null && node.text.isNotEmpty()) {
            sb.append(node.text.toString()).append("\n")
        }
        
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) readNode(child, sb, width, height)
        }
    }

    // (Keep the safe screenshot logic unchanged below)
    fun takeScreenshot(callback: (String?) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            try {
                takeScreenshot(
                    Display.DEFAULT_DISPLAY,
                    applicationContext.mainExecutor,
                    object : TakeScreenshotCallback {
                        override fun onSuccess(screenshotResult: ScreenshotResult) {
                            try {
                                val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                                    screenshotResult.hardwareBuffer,
                                    screenshotResult.colorSpace
                                )
                                val softwareBitmap = hardwareBitmap?.copy(Bitmap.Config.ARGB_8888, true)
                                screenshotResult.hardwareBuffer.close()
                                hardwareBitmap?.recycle()
                                if (softwareBitmap != null) {
                                    val path = saveBitmapToFile(softwareBitmap)
                                    softwareBitmap.recycle()
                                    callback(path)
                                } else { callback(null) }
                            } catch (e: Exception) { callback(null) }
                        }
                        override fun onFailure(errorCode: Int) { callback(null) }
                    }
                )
            } catch (e: Exception) { callback(null) }
        } else { callback(null) }
    }

    private fun saveBitmapToFile(bitmap: Bitmap): String? {
        try {
            val file = File(cacheDir, "screen_capture.png")
            if (file.exists()) file.delete()
            val outputStream = FileOutputStream(file)
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
            outputStream.flush()
            outputStream.close()
            return file.absolutePath
        } catch (e: IOException) { return null }
    }
}