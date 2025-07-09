package com.example.translate_app

import android.app.*
import android.content.*
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.provider.Settings
import android.speech.tts.TextToSpeech
import android.view.*
import android.widget.*
import androidx.core.app.NotificationCompat
import com.google.android.gms.ads.AdRequest
import com.google.android.gms.ads.AdView
import com.google.android.gms.ads.MobileAds
import kotlinx.coroutines.*
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.util.*

class FloatingService : Service() {

    private lateinit var windowManager: WindowManager
    private var floatingIconView: View? = null
    private var floatingWindowView: View? = null
    private lateinit var tts: TextToSpeech
    private var isTtsInitialized = false
    private var iconParams: WindowManager.LayoutParams? = null

    companion object {
        private const val NOTIFICATION_ID = 1
        private const val CHANNEL_ID = "floating_service_channel"
    }

    override fun onCreate() {
        super.onCreate()
        windowManager = getSystemService(WINDOW_SERVICE) as WindowManager
        MobileAds.initialize(this) {} // Initialize AdMob
        createNotificationChannel()
        startForegroundNotification()
        createFloatingIcon()
        initTTS()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Floating Translator Service",
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun startForegroundNotification() {
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Floating Translator")
            .setContentText("Service is running…")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        startForeground(NOTIFICATION_ID, notification)
    }

    private fun createFloatingIcon() {
        try {
            if (!checkOverlayPermission()) {
                Toast.makeText(this, "Overlay permission not granted. Please enable it.", Toast.LENGTH_LONG).show()
                requestOverlayPermission()
                return // Do not stop service; allow permission prompt
            }

            val inflater = getSystemService(LAYOUT_INFLATER_SERVICE) as LayoutInflater
            floatingIconView = inflater.inflate(R.layout.floating_icon_layout, null)

            iconParams = WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_APPLICATION,
                WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.TRANSLUCENT
            )
            iconParams?.gravity = Gravity.TOP or Gravity.START
            iconParams?.x = 0
            iconParams?.y = 100

            // Drag logic
            var initialX = 0
            var initialY = 0
            var initialTouchX = 0f
            var initialTouchY = 0f
            var lastActionDownTime = 0L
            val clickDuration = 200L // Max duration for a click (ms)

            floatingIconView?.setOnTouchListener { _, event ->
                when (event.action) {
                    MotionEvent.ACTION_DOWN -> {
                        initialX = iconParams?.x ?: 0
                        initialY = iconParams?.y ?: 0
                        initialTouchX = event.rawX
                        initialTouchY = event.rawY
                        lastActionDownTime = System.currentTimeMillis()
                        true
                    }
                    MotionEvent.ACTION_MOVE -> {
                        iconParams?.x = initialX + (event.rawX - initialTouchX).toInt()
                        iconParams?.y = initialY + (event.rawY - initialTouchY).toInt()
                        try {
                            windowManager.updateViewLayout(floatingIconView, iconParams)
                        } catch (e: Exception) {
                            e.printStackTrace()
                        }
                        true
                    }
                    MotionEvent.ACTION_UP -> {
                        if (System.currentTimeMillis() - lastActionDownTime < clickDuration) {
                            showFloatingWindow()
                        }
                        true
                    }
                    else -> false
                }
            }

            // Close button for floating icon
            floatingIconView?.findViewById<ImageView>(R.id.btn_icon_close)?.setOnClickListener {
                try {
                    stopSelf()
                } catch (e: Exception) {
                    e.printStackTrace()
                    Toast.makeText(this, "Failed to close: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }

            windowManager.addView(floatingIconView, iconParams)
        } catch (e: Exception) {
            e.printStackTrace()
            Toast.makeText(this, "Failed to create floating icon: ${e.message}", Toast.LENGTH_LONG).show()
            stopSelf()
        }
    }

    private fun checkOverlayPermission(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(this)
        } else {
            true // No permission needed below API 23
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
            } catch (e: Exception) {
                e.printStackTrace()
                Toast.makeText(this, "Failed to open permission settings: ${e.message}", Toast.LENGTH_LONG).show()
            }
        }
    }

    private fun initTTS() {
        tts = TextToSpeech(this) { status ->
            if (status == TextToSpeech.SUCCESS) {
                tts.language = Locale.US
                isTtsInitialized = true
            } else {
                Toast.makeText(this, "Text-to-Speech initialization failed", Toast.LENGTH_SHORT).show()
            }
        }
    }

    private fun showFloatingWindow() {
        if (floatingWindowView != null) return
        if (!checkOverlayPermission()) {
            Toast.makeText(this, "Overlay permission not granted. Please enable it.", Toast.LENGTH_LONG).show()
            requestOverlayPermission()
            return
        }

        try {
            val inflater = getSystemService(LAYOUT_INFLATER_SERVICE) as LayoutInflater
            floatingWindowView = inflater.inflate(R.layout.floating_window_layout, null)

            val displayMetrics = resources.displayMetrics
            val params = WindowManager.LayoutParams(
                (displayMetrics.widthPixels * 0.9).toInt(), // 90% of screen width
                WindowManager.LayoutParams.WRAP_CONTENT,
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                else
                    WindowManager.LayoutParams.TYPE_APPLICATION,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL or
                        WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
                PixelFormat.TRANSLUCENT
            )
            params.gravity = Gravity.CENTER

            // Close button
            floatingWindowView?.findViewById<ImageView>(R.id.btn_close)?.setOnClickListener {
                try {
                    floatingWindowView?.let { windowManager.removeView(it) }
                    floatingWindowView = null
                } catch (e: Exception) {
                    e.printStackTrace()
                    Toast.makeText(this, "Failed to close window: ${e.message}", Toast.LENGTH_SHORT).show()
                }
            }

            // Language spinner
            val spinner = floatingWindowView?.findViewById<Spinner>(R.id.languageSpinner)
            val languages = listOf("English", "Hindi", "Gujarati", "French")
            val adapter = ArrayAdapter(this, android.R.layout.simple_spinner_dropdown_item, languages)
            spinner?.adapter = adapter

            // Translate button
            val translateBtn = floatingWindowView?.findViewById<Button>(R.id.translateBtn)
            val inputText = floatingWindowView?.findViewById<EditText>(R.id.inputText)
            val translatedText = floatingWindowView?.findViewById<TextView>(R.id.translatedText)

            translateBtn?.setOnClickListener {
                val text = inputText?.text.toString()
                val lang = spinner?.selectedItem.toString() ?: "English"
                if (text.isNotEmpty()) {
                    translatedText?.text = "Translating..."
                    callGeminiApi(text, lang, translatedText)
                } else {
                    Toast.makeText(this, "Please enter text to translate", Toast.LENGTH_SHORT).show()
                }
            }

            // Play button
            val playBtn = floatingWindowView?.findViewById<Button>(R.id.playBtn)
            playBtn?.setOnClickListener {
                val text = translatedText?.text.toString()
                if (text.isNotEmpty() && text != "Translating..." && isTtsInitialized) {
                    tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, null)
                } else {
                    Toast.makeText(this, "No text to play or TTS not initialized", Toast.LENGTH_SHORT).show()
                }
            }

            // Copy button
            val copyBtn = floatingWindowView?.findViewById<Button>(R.id.copyBtn)
            copyBtn?.setOnClickListener {
                val text = translatedText?.text.toString()
                if (text.isNotEmpty() && text != "Translating...") {
                    val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
                    clipboard.setPrimaryClip(ClipData.newPlainText("translated", text))
                    Toast.makeText(this, "Copied to clipboard", Toast.LENGTH_SHORT).show()
                } else {
                    Toast.makeText(this, "No text to copy", Toast.LENGTH_SHORT).show()
                }
            }

            // AdView
            val adView = floatingWindowView?.findViewById<AdView>(R.id.adView)
            adView?.loadAd(AdRequest.Builder().build())

            windowManager.addView(floatingWindowView, params)
            // Add fade-in animation
            floatingWindowView?.alpha = 0f
            floatingWindowView?.animate()?.alpha(1f)?.setDuration(300)?.start()
        } catch (e: Exception) {
            e.printStackTrace()
            Toast.makeText(this, "Failed to show floating window: ${e.message}", Toast.LENGTH_LONG).show()
        }
    }

    private fun callGeminiApi(text: String, language: String, resultView: TextView?) {
        val apiKey = "AIzaSyAy5xW2-z_anLdPYhFixJZPO-PBWtDUE3w"
        val prompt = "Translate \"$text\" to $language. Return only the translated text."
        val urlString = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey"

        val safePrompt = JSONObject.quote(prompt)

        CoroutineScope(Dispatchers.IO).launch {
            var connection: HttpURLConnection? = null
            try {
                val url = URL(urlString)
                connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.doOutput = true
                connection.setRequestProperty("Content-Type", "application/json")
                connection.connectTimeout = 10000 // 10 seconds timeout
                connection.readTimeout = 10000

                val body = """
{
  "contents": [
    {
      "role": "user",
      "parts": [
        { "text": $safePrompt }
      ]
    }
  ]
}
""".trimIndent()
                connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }

                // Check response code
                val responseCode = connection.responseCode
                if (responseCode != HttpURLConnection.HTTP_OK) {
                    val errorMessage = connection.errorStream?.bufferedReader()?.readText() ?: "Unknown error"
                    throw Exception("HTTP $responseCode: $errorMessage")
                }

                val response = connection.inputStream.bufferedReader().readText()
                println("Gemini API Response: $response") // Log for debugging

                val jsonResponse = JSONObject(response)
                val candidates = jsonResponse.optJSONArray("candidates")
                if (candidates == null || candidates.length() == 0) {
                    throw Exception("No candidates found in response")
                }

                val content = candidates.getJSONObject(0).optJSONObject("content")
                if (content == null) {
                    throw Exception("No content found in candidate")
                }

                val parts = content.optJSONArray("parts")
                if (parts == null || parts.length() == 0) {
                    throw Exception("No parts found in content")
                }

                val replyText = parts.getJSONObject(0).optString("text", "No translation found")

                withContext(Dispatchers.Main) {
                    resultView?.text = replyText
                }
            } catch (e: Exception) {
                e.printStackTrace()
                withContext(Dispatchers.Main) {
                    resultView?.text = "Error: ${e.message}"
                    Toast.makeText(this@FloatingService, "Translation failed: ${e.message}", Toast.LENGTH_LONG).show()
                }
            } finally {
                connection?.disconnect()
            }
        }
    }

    override fun onDestroy() {
        super.onDestroy()
        try {
            floatingIconView?.let { windowManager.removeView(it) }
            floatingWindowView?.let { windowManager.removeView(it) }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        if (::tts.isInitialized) {
            tts.stop()
            tts.shutdown()
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null
}