package com.antigravity.samsung_m2070_printer

import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.net.Uri
import android.os.Bundle
import android.os.ParcelFileDescriptor
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.antigravity/samsung_m2070"
    private var pendingSharedPdfPath: String? = null
    private val executor = Executors.newSingleThreadExecutor()

    companion object {
        init {
            System.loadLibrary("spl_encoder")
        }
    }

    // Native C++ functions implemented in native_bridge.cpp
    private external fun nativeGetJobStartHeader(jobName: String): ByteArray
    private external fun nativeGetJobEndFooter(): ByteArray
    private external fun nativeEncodeBitmapPage(
        bitmap: Bitmap,
        copies: Int,
        resolutionDpi: Int,
        useDithering: Boolean
    ): ByteArray?

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent == null) return
        val action = intent.action
        val type = intent.type

        var uri: Uri? = null
        if (Intent.ACTION_SEND == action && type != null && type.contains("pdf")) {
            uri = intent.getParcelableExtra(Intent.EXTRA_STREAM)
        } else if (Intent.ACTION_VIEW == action) {
            uri = intent.data
        }

        if (uri != null) {
            val localPath = copyUriToInternalStorage(uri)
            if (localPath != null) {
                pendingSharedPdfPath = localPath
            }
        }
    }

    private fun copyUriToInternalStorage(uri: Uri): String? {
        return try {
            contentResolver.openInputStream(uri)?.use { inputStream ->
                val tempFile = File(cacheDir, "shared_document_${System.currentTimeMillis()}.pdf")
                FileOutputStream(tempFile).use { outputStream ->
                    inputStream.copyTo(outputStream)
                }
                tempFile.absolutePath
            }
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getInitialPdfPath" -> {
                    val path = pendingSharedPdfPath
                    pendingSharedPdfPath = null
                    result.success(path)
                }

                "getPdfPageCount" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }
                    executor.execute {
                        try {
                            val file = File(filePath)
                            val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            val renderer = PdfRenderer(pfd)
                            val count = renderer.pageCount
                            renderer.close()
                            pfd.close()
                            runOnUiThread { result.success(count) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RENDER_ERROR", e.message, null) }
                        }
                    }
                }

                "renderPagePreview" -> {
                    val filePath = call.argument<String>("filePath")
                    val pageIndex = call.argument<Int>("pageIndex") ?: 0
                    val targetWidth = call.argument<Int>("width") ?: 595
                    val targetHeight = call.argument<Int>("height") ?: 842

                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            val file = File(filePath)
                            val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            val renderer = PdfRenderer(pfd)
                            val page = renderer.openPage(pageIndex)

                            val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY)
                            page.close()
                            renderer.close()
                            pfd.close()

                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 90, stream)
                            val bytes = stream.toByteArray()
                            bitmap.recycle()

                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RENDER_ERROR", e.message, null) }
                        }
                    }
                }

                "getJobStartHeader" -> {
                    val jobName = call.argument<String>("jobName") ?: "Document.pdf"
                    executor.execute {
                        try {
                            val bytes = nativeGetJobStartHeader(jobName)
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ENCODE_ERROR", e.message, null) }
                        }
                    }
                }

                "getJobEndFooter" -> {
                    executor.execute {
                        try {
                            val bytes = nativeGetJobEndFooter()
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ENCODE_ERROR", e.message, null) }
                        }
                    }
                }

                "renderAndEncodePage" -> {
                    val filePath = call.argument<String>("filePath")
                    val pageIndex = call.argument<Int>("pageIndex") ?: 0
                    val copies = call.argument<Int>("copies") ?: 1
                    val resolutionDpi = call.argument<Int>("resolutionDpi") ?: 600
                    val useDithering = call.argument<Boolean>("useDithering") ?: true

                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    // A4 size @ 600 DPI = 4960 x 7016, @ 300 DPI = 2480 x 3508
                    val width = if (resolutionDpi == 300) 2480 else 4960
                    val height = if (resolutionDpi == 300) 3508 else 7016

                    executor.execute {
                        try {
                            val file = File(filePath)
                            val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            val renderer = PdfRenderer(pfd)
                            val page = renderer.openPage(pageIndex)

                            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.WHITE)
                            page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                            page.close()
                            renderer.close()
                            pfd.close()

                            // Native JBIG1 + QPDL encoding
                            val encodedBytes = nativeEncodeBitmapPage(bitmap, copies, resolutionDpi, useDithering)
                            bitmap.recycle()

                            if (encodedBytes != null) {
                                runOnUiThread { result.success(encodedBytes) }
                            } else {
                                runOnUiThread { result.error("ENCODE_FAILED", "Native encoding returned null", null) }
                            }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("RENDER_ENCODE_ERROR", e.message, null) }
                        }
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
