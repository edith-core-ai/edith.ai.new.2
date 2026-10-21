package com.example.edith_app

import android.app.Notification
import android.content.pm.PackageManager
import android.os.Build
import android.provider.ContactsContract
import android.provider.Settings
import android.telephony.SmsManager
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val ACCESS_CHANNEL = "edith/accessibility"
    private val NATIVE_CHANNEL = "edith/native_tools"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ───── Accessibility channel ─────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACCESS_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> {
                        // running: the service is alive and usable.
                        // enabled: switched on in Settings but not running
                        //          (phone stopped it, or it crashed).
                        // off: not switched on.
                        val listed = (Settings.Secure.getString(
                            contentResolver,
                            Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
                        ) ?: "").contains("EdithAccessibilityService")
                        result.success(
                            when {
                                EdithAccessibilityService.instance != null -> "running"
                                listed -> "enabled"
                                else -> "off"
                            }
                        )
                    }
                    "isEnabled" -> result.success(
                        EdithAccessibilityService.instance != null
                    )
                    "performBack" -> {
                        EdithAccessibilityService.instance?.performGlobalAction(
                            android.accessibilityservice.AccessibilityService
                                .GLOBAL_ACTION_BACK
                        )
                        result.success(true)
                    }
                    "performHome" -> {
                        EdithAccessibilityService.instance?.performGlobalAction(
                            android.accessibilityservice.AccessibilityService
                                .GLOBAL_ACTION_HOME
                        )
                        result.success(true)
                    }
                    "performRecents" -> {
                        EdithAccessibilityService.instance?.performGlobalAction(
                            android.accessibilityservice.AccessibilityService
                                .GLOBAL_ACTION_RECENTS
                        )
                        result.success(true)
                    }
                    "readScreen" -> {
                        result.success(
                            EdithAccessibilityService.instance?.readScreenText()
                        )
                    }
                    "tapByText" -> {
                        val target = call.argument<String>("text") ?: ""
                        result.success(
                            EdithAccessibilityService.instance?.tapByText(target) ?: false
                        )
                    }
                    "typeIntoFocused" -> {
                        val text = call.argument<String>("text") ?: ""
                        result.success(
                            EdithAccessibilityService.instance?.typeIntoFocused(text) ?: false
                        )
                    }
                    "scroll" -> {
                        val fwd = call.argument<Boolean>("forward") ?: true
                        result.success(
                            EdithAccessibilityService.instance?.scroll(fwd) ?: false
                        )
                    }
                    "screenshot" -> {
                        val svc = EdithAccessibilityService.instance
                        if (svc == null) result.success(null)
                        else svc.screenshot { b64 -> result.success(b64) }
                    }
                    "currentApp" -> result.success(
                        EdithAccessibilityService.instance?.currentPackage() ?: ""
                    )
                    "launchApp" -> {
                        val name = (call.argument<String>("name") ?: "").trim()
                        result.success(launchAppByName(name))
                    }
                    else -> result.notImplemented()
                }
            }

        // ───── Native tools channel (Tier 3) ─────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NATIVE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {

                    "sendSms" -> {
                        val phone = call.argument<String>("phone") ?: ""
                        val message = call.argument<String>("message") ?: ""
                        val hasPerm = ContextCompat.checkSelfPermission(
                            this, android.Manifest.permission.SEND_SMS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!hasPerm) {
                            result.error("PERMISSION_DENIED", "SEND_SMS not granted", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val sms: SmsManager = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                getSystemService(SmsManager::class.java)
                            } else {
                                @Suppress("DEPRECATION")
                                SmsManager.getDefault()
                            }
                            val parts = sms.divideMessage(message)
                            if (parts.size > 1) {
                                sms.sendMultipartTextMessage(phone, null, parts, null, null)
                            } else {
                                sms.sendTextMessage(phone, null, message, null, null)
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SMS_FAILED", e.message, null)
                        }
                    }

                    "readContacts" -> {
                        val hasPerm = ContextCompat.checkSelfPermission(
                            this, android.Manifest.permission.READ_CONTACTS
                        ) == PackageManager.PERMISSION_GRANTED
                        if (!hasPerm) {
                            result.error("PERMISSION_DENIED", "READ_CONTACTS not granted", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val list = mutableListOf<Map<String, String>>()
                            val cursor = contentResolver.query(
                                ContactsContract.CommonDataKinds.Phone.CONTENT_URI,
                                arrayOf(
                                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME,
                                    ContactsContract.CommonDataKinds.Phone.NUMBER
                                ),
                                null, null,
                                ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME + " ASC"
                            )
                            cursor?.use {
                                val nameIdx = it.getColumnIndex(
                                    ContactsContract.CommonDataKinds.Phone.DISPLAY_NAME
                                )
                                val numIdx = it.getColumnIndex(
                                    ContactsContract.CommonDataKinds.Phone.NUMBER
                                )
                                while (it.moveToNext()) {
                                    val name = it.getString(nameIdx) ?: ""
                                    val number = it.getString(numIdx) ?: ""
                                    if (name.isNotEmpty() && number.isNotEmpty()) {
                                        list.add(mapOf("name" to name, "number" to number))
                                    }
                                }
                            }
                            result.success(list)
                        } catch (e: Exception) {
                            result.error("CONTACTS_FAILED", e.message, null)
                        }
                    }

                    "isNotificationListenerEnabled" -> {
                        val flat = Settings.Secure.getString(
                            contentResolver,
                            "enabled_notification_listeners"
                        )
                        result.success(flat?.contains(packageName) == true)
                    }

                    "readNotifications" -> {
                        val limit = call.argument<Int>("limit") ?: 10
                        result.success(EdithNotificationListenerService.getRecent(limit))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /// Finds an installed app by its visible name ("WhatsApp", "settings")
    /// and opens it. Returns the app's real name, or null if not found.
    private fun launchAppByName(name: String): String? {
        if (name.isEmpty()) return null
        val pm = packageManager
        val main = android.content.Intent(android.content.Intent.ACTION_MAIN)
            .addCategory(android.content.Intent.CATEGORY_LAUNCHER)
        val apps = pm.queryIntentActivities(main, 0)
        val want = name.lowercase()
        var best: android.content.pm.ResolveInfo? = null
        var bestScore = 0
        for (ri in apps) {
            val label = ri.loadLabel(pm).toString().lowercase()
            val score = when {
                label == want -> 3
                label.startsWith(want) -> 2
                label.contains(want) || want.contains(label) -> 1
                else -> 0
            }
            if (score > bestScore) { best = ri; bestScore = score }
        }
        val hit = best ?: return null
        val intent = pm.getLaunchIntentForPackage(hit.activityInfo.packageName)
            ?: return null
        intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        startActivity(intent)
        return hit.loadLabel(pm).toString()
    }
}
