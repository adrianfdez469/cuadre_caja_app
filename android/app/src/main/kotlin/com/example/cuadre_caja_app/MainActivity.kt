package com.example.cuadre_caja_app

import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.RandomAccessFile
import kotlin.system.exitProcess

class MainActivity : FlutterActivity() {

    private val channel = "com.example.cuadre_caja_app/native"

    /** Ruta del APK desde el que arrancó ESTE proceso. Android le da a cada
     *  instalación un directorio nuevo, así que si el archivo desaparece es que
     *  el APK se reemplazó por debajo y seguimos ejecutando código viejo. */
    private var startupSourceDir: String? = null

    /** versionCode instalado cuando arrancó este proceso. Al arrancar coincide
     *  con el código que estamos ejecutando; si luego difiere, hubo una
     *  actualización. */
    private var startupVersionCode: Long = 0L

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (startupSourceDir == null) {
            startupSourceDir = applicationInfo.sourceDir
            startupVersionCode = installedVersionCode()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAndroidAbi" -> {
                    val abi = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                        Build.SUPPORTED_ABIS.firstOrNull() ?: Build.CPU_ABI
                    } else {
                        @Suppress("DEPRECATION")
                        Build.CPU_ABI
                    }
                    result.success(abi)
                }
                "validateApkForUpdate" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "apkPath required", null)
                        return@setMethodCallHandler
                    }
                    result.success(validateApkForUpdate(apkPath))
                }
                "installApk" -> {
                    val apkPath = call.argument<String>("apkPath")
                    if (apkPath.isNullOrBlank()) {
                        result.error("INVALID_ARGS", "apkPath required", null)
                        return@setMethodCallHandler
                    }
                    result.success(installApk(apkPath))
                }
                "checkStaleBuild" -> {
                    result.success(checkStaleBuild())
                }
                "closeApp" -> {
                    result.success(null)
                    closeApp()
                }
                "canInstallFromUnknownSources" -> {
                    result.success(canInstallFromUnknownSources())
                }
                "openUnknownSourcesSettings" -> {
                    openUnknownSourcesSettings()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun validateApkForUpdate(apkPath: String): Map<String, Any?> {
        val file = File(apkPath)
        if (!file.exists() || !isValidApkFile(file)) {
            return mapOf(
                "canInstall" to false,
                "reason" to "invalid_apk",
            )
        }

        val pm = packageManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES
        }

        @Suppress("DEPRECATION")
        val archiveInfo = pm.getPackageArchiveInfo(apkPath, flags)
            ?: return mapOf(
                "canInstall" to false,
                "reason" to "invalid_apk",
            )

        archiveInfo.applicationInfo?.let { appInfo ->
            appInfo.sourceDir = apkPath
            appInfo.publicSourceDir = apkPath
        }

        if (archiveInfo.packageName != packageName) {
            return mapOf(
                "canInstall" to false,
                "reason" to "package_mismatch",
                "apkVersionName" to archiveInfo.versionName,
            )
        }

        val apkVersionCode = getVersionCode(archiveInfo)
        val installedVersionCode = try {
            val installed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                pm.getPackageInfo(packageName, 0)
            } else {
                @Suppress("DEPRECATION")
                pm.getPackageInfo(packageName, 0)
            }
            getVersionCode(installed)
        } catch (_: Exception) {
            0L
        }

        if (apkVersionCode <= installedVersionCode) {
            return mapOf(
                "canInstall" to false,
                "reason" to "version_downgrade",
                "apkVersionCode" to apkVersionCode.toInt(),
                "installedVersionCode" to installedVersionCode.toInt(),
                "apkVersionName" to archiveInfo.versionName,
            )
        }

        if (!canInstallFromUnknownSources()) {
            return mapOf(
                "canInstall" to false,
                "reason" to "unknown_sources_blocked",
                "apkVersionCode" to apkVersionCode.toInt(),
                "installedVersionCode" to installedVersionCode.toInt(),
                "apkVersionName" to archiveInfo.versionName,
            )
        }

        return mapOf(
            "canInstall" to true,
            "apkVersionCode" to apkVersionCode.toInt(),
            "installedVersionCode" to installedVersionCode.toInt(),
            "apkVersionName" to archiveInfo.versionName,
        )
    }

    private fun installApk(apkPath: String): Boolean {
        if (!canInstallFromUnknownSources()) {
            openUnknownSourcesSettings()
            return false
        }

        val file = File(apkPath)
        if (!file.exists() || !isValidApkFile(file)) return false

        val uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }

        return try {
            startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    /// Detecta si este proceso quedó huérfano: el APK que lo lanzó ya no es el
    /// instalado. Pasa cuando Android instala la actualización sin matar el
    /// proceso viejo; si no se cierra, conviven dos versiones de la app sobre
    /// la misma base de datos.
    private fun checkStaleBuild(): Map<String, Any?> {
        val installed = installedVersionCode()
        val sourceDir = startupSourceDir
        // El APK de arranque borrado pesa más que el versionCode: PackageManager
        // cachea por proceso y puede seguir devolviendo el valor viejo.
        val sourceGone = sourceDir != null && !File(sourceDir).exists()
        val versionChanged =
            startupVersionCode > 0L && installed > 0L && installed != startupVersionCode
        val stale = sourceGone || versionChanged

        var versionName: String? = null
        if (stale) {
            versionName = try {
                packageManager.getPackageInfo(packageName, 0).versionName
            } catch (_: Exception) {
                null
            }
        }
        return mapOf(
            "stale" to stale,
            "runningVersionCode" to startupVersionCode.toInt(),
            "installedVersionCode" to installed.toInt(),
            "installedVersionName" to versionName,
        )
    }

    /// Cierra la app quitándola además de "recientes", para que no quede la
    /// tarjeta de la versión vieja invitando a reabrirla. El exit es necesario:
    /// sin él el proceso sigue vivo en segundo plano sincronizando.
    private fun closeApp() {
        finishAndRemoveTask()
        Handler(Looper.getMainLooper()).postDelayed({ exitProcess(0) }, 300)
    }

    private fun installedVersionCode(): Long {
        return try {
            getVersionCode(packageManager.getPackageInfo(packageName, 0))
        } catch (_: Exception) {
            0L
        }
    }

    private fun canInstallFromUnknownSources(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun openUnknownSourcesSettings() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                data = Uri.parse("package:$packageName")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            try {
                startActivity(intent)
            } catch (_: Exception) {
                val fallback = Intent(Settings.ACTION_SECURITY_SETTINGS).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                try {
                    startActivity(fallback)
                } catch (_: Exception) {
                    // Sin acción
                }
            }
        }
    }

    private fun isValidApkFile(file: File): Boolean {
        if (file.length() < 100 * 1024) return false
        return try {
            RandomAccessFile(file, "r").use { raf ->
                val header = ByteArray(2)
                if (raf.read(header) != 2) return false
                header[0] == 'P'.code.toByte() && header[1] == 'K'.code.toByte()
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun getVersionCode(info: android.content.pm.PackageInfo): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            info.longVersionCode
        } else {
            @Suppress("DEPRECATION")
            info.versionCode.toLong()
        }
    }
}
