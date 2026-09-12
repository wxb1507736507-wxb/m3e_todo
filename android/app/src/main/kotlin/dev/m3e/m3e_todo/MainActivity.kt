package dev.m3e.m3e_todo

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts the Flutter UI and answers the one question Dart cannot answer on its
 * own: where this app is allowed to keep its files.
 *
 * Android gives every app a private directory, but that path is not derivable
 * from the environment the way `%APPDATA%` is on Windows — it has to be asked of
 * the Activity. A plain [MethodChannel] declared right here does the job without
 * adding `path_provider`.
 *
 * Avoiding that plugin is deliberate. Plugins make Flutter create symlinks under
 * `windows/flutter/ephemeral/.plugin_symlinks`, which on Windows requires
 * Developer Mode or an elevated prompt, and this project is meant to build with
 * nothing but the Visual Studio C++ workload installed. Keeping the channel in
 * the app's own shell costs about twenty lines and no dependencies.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val STORAGE_CHANNEL = "dev.m3e.m3e_todo/storage"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, STORAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    // filesDir is private to the app and removed when the app is
                    // uninstalled, which is the correct place for user data that
                    // is not meant to be shared or backed up elsewhere.
                    "getDataDirectory" -> result.success(filesDir.absolutePath)
                    else -> result.notImplemented()
                }
            }
    }
}
