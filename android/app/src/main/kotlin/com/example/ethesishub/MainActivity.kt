package com.example.ethesishub

import android.os.Build
import android.widget.Toast
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Owns the Android back gesture so a stray swipe cannot drop the reader out of
 * the app.
 *
 * This lives in native code on purpose. The app routes with go_router, whose
 * ShellRoute reports "nothing to pop" to Android at a top-level destination
 * (its nested navigator holds a single page), so Android finishes the activity
 * BEFORE any Dart PopScope or BackButtonListener is consulted — a single swipe
 * closed the app and no Dart guard could catch it. Handling back here runs
 * first, whatever the router reports.
 *
 * Two back paths are wired up, because `FlutterActivity` is a plain
 * `android.app.Activity` — not AndroidX's `ComponentActivity` — so it has no
 * `onBackPressedDispatcher` to hang a modern `OnBackPressedCallback` off of.
 *
 * - SDK < 33: the legacy `onBackPressed()` override below, same as always.
 * - SDK 33+ (Android 13+): a platform `OnBackInvokedCallback` registered
 *   directly with `getOnBackInvokedDispatcher()`. Apps targeting API 36
 *   running on an Android 16+ device get predictive-back system animations
 *   by default, and the platform stops calling `onBackPressed()` and
 *   dispatching `KEYCODE_BACK` entirely — see
 *   https://developer.android.com/about/versions/16/behavior-changes-16#back-nav.
 *   That's why the toast wasn't showing: on that combination `onBackPressed()`
 *   was simply never invoked and the swipe fell straight through to finishing
 *   the activity. Registering the platform callback is the "supported back
 *   navigation API" Android asks apps to migrate to for that case.
 *
 * The two paths don't double-fire: on a device where the OS hasn't switched
 * this activity onto the new dispatch path (SDK 33–35 here, since the
 * manifest doesn't opt in), the registered `OnBackInvokedCallback` simply
 * never gets invoked and `onBackPressed()` keeps firing as before; on
 * Android 16+ it's the reverse.
 *
 * On every back (the gesture or the on-screen back button) it asks Dart first.
 * Dart pops a pushed screen, or from any other page goes to the dashboard, and
 * answers true. Only when Dart answers false — on the dashboard, or signed
 * out — does this warn once and exit on a confirming second back within
 * EXIT_WINDOW_MS.
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var lastBackAt = 0L
    private var toast: Toast? = null

    companion object {
        private const val CHANNEL = "app/navigation"
        private const val EXIT_WINDOW_MS = 2000L
    }

    private val backCallback = OnBackInvokedCallback { handleBack() }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerPlatformBackCallback()
        }
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun registerPlatformBackCallback() {
        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_OVERLAY,
            backCallback,
        )
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            onBackInvokedDispatcher.unregisterOnBackInvokedCallback(backCallback)
        }
        super.onDestroy()
    }

    @Deprecated("Legacy back path for SDK < 33; SDK 33+ is handled by the registered OnBackInvokedCallback instead.")
    override fun onBackPressed() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            super.onBackPressed()
            return
        }
        handleBack()
    }

    private fun handleBack() {
        val ch = channel
        if (ch == null) {
            confirmOrExit()
            return
        }
        // Ask Dart to pop a pushed screen. It answers true when it did, false
        // at a top-level destination.
        ch.invokeMethod("popRoute", null, object : MethodChannel.Result {
            override fun success(result: Any?) {
                if (result != true) confirmOrExit()
            }

            override fun error(code: String, message: String?, details: Any?) {
                confirmOrExit()
            }

            override fun notImplemented() {
                confirmOrExit()
            }
        })
    }

    /** Double-back to exit: the first back warns, a second within the window leaves. */
    private fun confirmOrExit() {
        val now = System.currentTimeMillis()
        if (now - lastBackAt <= EXIT_WINDOW_MS) {
            toast?.cancel()
            finish()
            return
        }
        lastBackAt = now
        toast?.cancel()
        toast = Toast.makeText(this, "Press back again to close the app", Toast.LENGTH_SHORT)
        toast?.show()
    }
}