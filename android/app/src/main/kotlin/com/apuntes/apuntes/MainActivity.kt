package com.apuntes.apuntes

import android.content.ClipboardManager
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.view.MotionEvent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "opennote/updater")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" ->
                        result.success(Build.VERSION.SDK_INT < Build.VERSION_CODES.O ||
                            packageManager.canRequestPackageInstalls())
                    "openInstallSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:$packageName"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    }
                    "install" -> try {
                        val uri = FileProvider.getUriForFile(this, "$packageName.updates", File(call.arguments as String))
                        startActivity(
                            Intent(Intent.ACTION_VIEW)
                                .setDataAndType(uri, "application/vnd.android.package-archive")
                                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
                        )
                        result.success(null)
                    } catch (e: Exception) {
                        result.error("install", e.message, null)
                    }
                    else -> result.notImplemented()
                }
            }

        // Portapapeles del sistema: solo imágenes (capturas, imágenes copiadas de otra app)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "opennote/clipboard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasImage" -> result.success(try { clipImageUri() != null } catch (e: Exception) { false })
                    "readImage" -> Thread {
                        val bytes = try {
                            clipImageUri()?.let { contentResolver.openInputStream(it)?.use { s -> s.readBytes() } }
                        } catch (e: Exception) {
                            null
                        }
                        runOnUiThread { result.success(bytes) }
                    }.start()
                    else -> result.notImplemented()
                }
            }
    }

    // Uri de la imagen que hay en el portapapeles (primer item), o null si no hay imagen
    private fun clipImageUri(): Uri? {
        val cm = getSystemService(CLIPBOARD_SERVICE) as ClipboardManager
        val clip = cm.primaryClip ?: return null
        if (clip.itemCount == 0) return null
        val uri = clip.getItemAt(0).uri ?: return null
        val d = cm.primaryClipDescription
        val byDesc = d?.let { x -> (0 until x.mimeTypeCount).any { x.getMimeType(it).startsWith("image/") } } ?: false
        return if (byDesc || contentResolver.getType(uri)?.startsWith("image/") == true) uri else null
    }

    // Lápiz sin esperar al cuadro: Android entrega sus movimientos apenas pasan en vez de juntarlos hasta el
    // próximo vsync (hasta ~16 ms menos de demora en la tinta). Se pide en cada gesto, al apoyar. El dedo y el mouse quedan como siempre.
    override fun dispatchTouchEvent(ev: MotionEvent): Boolean {
        if (ev.actionMasked == MotionEvent.ACTION_DOWN) {
            val tool = ev.getToolType(0)
            if (tool == MotionEvent.TOOL_TYPE_STYLUS || tool == MotionEvent.TOOL_TYPE_ERASER) {
                window.decorView.requestUnbufferedDispatch(ev)
            }
        }
        return super.dispatchTouchEvent(ev)
    }
}
