package com.example.cuadre_caja_app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val channel = "com.example.cuadre_caja_app/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            if (call.method == "getAndroidAbi") {
                val abi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    Build.SUPPORTED_ABIS.firstOrNull() ?: Build.CPU_ABI
                } else {
                    @Suppress("DEPRECATION")
                    Build.CPU_ABI
                }
                result.success(abi)
            } else {
                result.notImplemented()
            }
        }
    }
}
