package com.example.edith_app

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Bitmap
import android.graphics.Path
import android.os.Build
import android.util.Base64
import android.view.Display
import java.io.ByteArrayOutputStream
import android.graphics.Rect
import android.os.Bundle
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo

/**
 * EDITH's hands and eyes on the phone.
 *
 * Perception: [readScreenText] returns a short, numbered list of what is
 * visible, marked as tap-able, typing field or plain text.
 * Actions: tap by text (exact match first), type, scroll, global buttons.
 */
class EdithAccessibilityService : AccessibilityService() {
    companion object {
        var instance: EdithAccessibilityService? = null
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
    }

    override fun onDestroy() {
        instance = null
        super.onDestroy()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {}
    override fun onInterrupt() {}

    // ───────────── Perception ─────────────

    /** Screenshot of whatever is on screen, as a base64 JPEG (API 30+). */
    @android.annotation.SuppressLint("NewApi")
    fun screenshot(done: (String?) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) {
            done(null); return
        }
        try {
            takeScreenshot(
                Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(shot: ScreenshotResult) {
                        try {
                            val hw = Bitmap.wrapHardwareBuffer(
                                shot.hardwareBuffer, shot.colorSpace
                            )
                            if (hw == null) { done(null); return }
                            val soft = hw.copy(Bitmap.Config.ARGB_8888, false)
                            shot.hardwareBuffer.close()
                            val w = 720
                            val h = (soft.height * (w.toFloat() / soft.width)).toInt()
                            val small = Bitmap.createScaledBitmap(soft, w, h, true)
                            val out = ByteArrayOutputStream()
                            small.compress(Bitmap.CompressFormat.JPEG, 60, out)
                            done(Base64.encodeToString(out.toByteArray(), Base64.NO_WRAP))
                        } catch (e: Exception) {
                            done(null)
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        done(null)
                    }
                }
            )
        } catch (e: Exception) {
            done(null)
        }
    }

    fun currentPackage(): String =
        rootInActiveWindow?.packageName?.toString() ?: ""

    fun readScreenText(): String {
        val root = rootInActiveWindow ?: return ""
        val sb = StringBuilder()
        sb.append("APP: ").append(root.packageName ?: "unknown").append('\n')
        val counter = intArrayOf(0)
        walk(root, sb, 0, counter)
        return sb.toString()
    }

    private fun label(node: AccessibilityNodeInfo): String {
        val t = node.text?.toString()
        if (!t.isNullOrBlank()) return t.trim()
        val d = node.contentDescription?.toString()
        if (!d.isNullOrBlank()) return d.trim()
        val h = node.hintText?.toString()
        if (!h.isNullOrBlank()) return h.trim()
        return ""
    }

    private fun walk(
        node: AccessibilityNodeInfo?,
        sb: StringBuilder,
        depth: Int,
        counter: IntArray
    ) {
        if (node == null || depth > 40 || counter[0] >= 120) return
        if (!node.isVisibleToUser) return
        val text = label(node)
        val editable = node.isEditable
        val clickable = node.isClickable || node.isCheckable
        if (text.isNotEmpty() || editable) {
            counter[0]++
            val kind = when {
                editable -> "FIELD"
                clickable -> "TAP"
                else -> "TEXT"
            }
            sb.append('[').append(counter[0]).append("] ").append(kind)
                .append(": ")
            sb.append(if (text.isEmpty()) "(empty)" else text.take(120))
            if (node.isChecked) sb.append(" (on)")
            sb.append('\n')
        }
        for (i in 0 until node.childCount) {
            walk(node.getChild(i), sb, depth + 1, counter)
        }
    }

    // ───────────── Actions ─────────────

    fun tapByText(target: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val matches = ArrayList<AccessibilityNodeInfo>()
        collect(root, target.trim(), matches, 0)
        if (matches.isEmpty()) return false

        // Exact matches first, then the shortest label (closest match).
        val sorted = matches.sortedWith(
            compareBy({ !label(it).equals(target.trim(), true) },
                { label(it).length })
        )
        for (node in sorted) {
            var c: AccessibilityNodeInfo? = node
            while (c != null && !c.isClickable) c = c.parent
            if (c != null && c.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true
            }
        }
        // Nothing reported itself clickable: tap the middle of the best match.
        return tapCenter(sorted.first())
    }

    private fun collect(
        node: AccessibilityNodeInfo?,
        target: String,
        out: MutableList<AccessibilityNodeInfo>,
        depth: Int
    ) {
        if (node == null || depth > 40) return
        if (node.isVisibleToUser &&
            label(node).contains(target, ignoreCase = true)
        ) out.add(node)
        for (i in 0 until node.childCount) {
            collect(node.getChild(i), target, out, depth + 1)
        }
    }

    private fun tapCenter(node: AccessibilityNodeInfo): Boolean {
        val r = Rect()
        node.getBoundsInScreen(r)
        if (r.isEmpty) return false
        val path = Path()
        path.moveTo(r.exactCenterX(), r.exactCenterY())
        val stroke = GestureDescription.StrokeDescription(path, 0, 60)
        return dispatchGesture(
            GestureDescription.Builder().addStroke(stroke).build(),
            null, null
        )
    }

    fun typeIntoFocused(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        var field = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
        if (field == null) {
            field = firstEditable(root, 0)
            field?.performAction(AccessibilityNodeInfo.ACTION_CLICK)
            field?.performAction(AccessibilityNodeInfo.ACTION_FOCUS)
        }
        if (field == null) return false
        val args = Bundle()
        args.putCharSequence(
            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
            text
        )
        return field.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    private fun firstEditable(
        node: AccessibilityNodeInfo?,
        depth: Int
    ): AccessibilityNodeInfo? {
        if (node == null || depth > 40) return null
        if (node.isEditable && node.isVisibleToUser) return node
        for (i in 0 until node.childCount) {
            val r = firstEditable(node.getChild(i), depth + 1)
            if (r != null) return r
        }
        return null
    }

    fun scroll(forward: Boolean): Boolean {
        val root = rootInActiveWindow ?: return false
        val node = firstScrollable(root, 0) ?: return false
        return node.performAction(
            if (forward) AccessibilityNodeInfo.ACTION_SCROLL_FORWARD
            else AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD
        )
    }

    private fun firstScrollable(
        node: AccessibilityNodeInfo?,
        depth: Int
    ): AccessibilityNodeInfo? {
        if (node == null || depth > 40) return null
        if (node.isScrollable && node.isVisibleToUser) return node
        for (i in 0 until node.childCount) {
            val r = firstScrollable(node.getChild(i), depth + 1)
            if (r != null) return r
        }
        return null
    }
}
