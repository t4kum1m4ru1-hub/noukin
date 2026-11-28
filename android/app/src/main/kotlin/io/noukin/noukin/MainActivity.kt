package io.noukin.noukin

import android.media.AudioManager
import android.media.ToneGenerator
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        private const val CHANNEL = "io.noukin.noukin/key_events"

        private val TARGET_KEY_CODES = setOf(
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE, // 85
            KeyEvent.KEYCODE_HEADSETHOOK,      // 79
            KeyEvent.KEYCODE_VOLUME_UP,        // 24
            KeyEvent.KEYCODE_VOLUME_DOWN,      // 25
            KeyEvent.KEYCODE_MEDIA_NEXT,       // 87
            KeyEvent.KEYCODE_MEDIA_PREVIOUS    // 88
        )
    }

    private var methodChannel: MethodChannel? = null
    private var toneGenerator: ToneGenerator? = null
    private var isKeyInterceptionEnabled = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
        } catch (_: Exception) {
            toneGenerator = null
        }

        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "playBeep" -> {
                        try {
                            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 45)
                            result.success(true)
                        } catch (_: Exception) {
                            result.success(false)
                        }
                    }
                    "setKeyInterceptionEnabled" -> {
                        isKeyInterceptionEnabled = (call.arguments as? Boolean) ?: false
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        isKeyInterceptionEnabled = false
        methodChannel?.setMethodCallHandler(null)
        methodChannel = null
        try {
            toneGenerator?.release()
        } catch (_: Exception) {
        }
        toneGenerator = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val keyCode = event.keyCode
        if (isKeyInterceptionEnabled && keyCode in TARGET_KEY_CODES) {
            // 初回押し込み時のみ Flutter 側へキーコードを通知（長押しリピートや離した時は通知しない）
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                methodChannel?.invokeMethod("onKeyEvent", keyCode)
            }
            // OS デフォルトの処理（音量変更や標準メディア操作）を抑止
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
