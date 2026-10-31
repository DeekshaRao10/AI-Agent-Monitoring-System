package com.example.safeband

import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val volumeChannelName = "com.example.safeband/volume_silence"
    private var methodChannel: MethodChannel? = null

    // Only true while EmergencyScreen is actually mounted (Dart sets this
    // via the channel below on open/close) — volume keys behave
    // completely normally everywhere else in the app.
    private var interceptVolumeKeys = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Lets this activity actually display OVER the lock screen and
        // wake the phone when Android launches it via the fall-alert
        // notification's full-screen intent (see notification_service.dart,
        // fullScreenIntent: true). Without this, granting the "Full screen
        // notifications" permission isn't enough on its own — Android still
        // accepts the request and launches this activity, but it just sits
        // there behind the still-locked lock screen, invisible until
        // someone manually unlocks the phone. Same mechanism an incoming
        // call screen uses to appear immediately.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Lets EmergencyScreen silence the siren/vibration with a volume
        // button press without closing the screen — the same "press
        // volume to silence" gesture phones use for an incoming call or
        // alarm. Flutter never receives raw hardware key events on
        // Android by default, so this has to be intercepted natively and
        // relayed over to Dart.
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, volumeChannelName)
        methodChannel?.setMethodCallHandler { call, result ->
            if (call.method == "setVolumeInterceptionEnabled") {
                interceptVolumeKeys = call.arguments as? Boolean ?: false
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        if (interceptVolumeKeys &&
            event.action == KeyEvent.ACTION_DOWN &&
            (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP ||
                event.keyCode == KeyEvent.KEYCODE_VOLUME_DOWN)
        ) {
            methodChannel?.invokeMethod("volumeKeyPressed", null)
            // Consumed — otherwise Android would also pop up its own
            // volume UI overlay for a press that's meant to silence the
            // alert, not adjust media volume.
            return true
        }
        return super.dispatchKeyEvent(event)
    }
}
