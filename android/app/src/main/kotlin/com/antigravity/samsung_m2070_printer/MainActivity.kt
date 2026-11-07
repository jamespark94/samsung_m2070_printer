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
    private var methodChannel: MethodChannel? = null
    private val executor = Executors.newSingleThreadExecutor()

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
                methodChannel?.invokeMethod("onSharedPdfReceived", localPath)
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

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                            val slices = PdfLayoutHelper.buildVirtualPageList(renderer)
                            val count = slices.size
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
                    val targetWidth = call.argument<Int>("width") ?: 1190
                    val targetHeight = call.argument<Int>("height") ?: 1684
                    val darkThemeMode = call.argument<String>("darkThemeMode") ?: "auto"

                    if (filePath == null) {
                        result.error("INVALID_ARGS", "filePath is required", null)
                        return@setMethodCallHandler
                    }

                    executor.execute {
                        try {
                            val file = File(filePath)
                            val pfd = ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
                            val renderer = PdfRenderer(pfd)
                            val slices = PdfLayoutHelper.buildVirtualPageList(renderer)

                            val slice = if (pageIndex in slices.indices) slices[pageIndex] else slices.firstOrNull()
                            if (slice == null) {
                                renderer.close()
                                pfd.close()
                                runOnUiThread { result.error("INVALID_PAGE", "No pages found", null) }
                                return@execute
                            }

                            val bitmap = PdfLayoutHelper.renderVirtualPage(
                                renderer,
                                slice,
                                targetWidth,
                                targetHeight,
                                forPrint = false
                            )
                            renderer.close()
                            pfd.close()

                            PdfLayoutHelper.applySmartDarkThemeInversion(bitmap, darkThemeMode)

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
                            val bytes = SplNativeBridge.nativeGetJobStartHeader(jobName)
                            runOnUiThread { result.success(bytes) }
                        } catch (e: Exception) {
                            runOnUiThread { result.error("ENCODE_ERROR", e.message, null) }
                        }
                    }
                }

                "getJobEndFooter" -> {
                    executor.execute {
                        try {
                            val bytes = SplNativeBridge.nativeGetJobEndFooter()
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
                    val darkThemeMode = call.argument<String>("darkThemeMode") ?: "auto"

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
                            val slices = PdfLayoutHelper.buildVirtualPageList(renderer)

                            val slice = if (pageIndex in slices.indices) slices[pageIndex] else slices.firstOrNull()
                            if (slice == null) {
                                renderer.close()
                                pfd.close()
                                runOnUiThread { result.error("INVALID_PAGE", "No pages found", null) }
                                return@execute
                            }

                            val bitmap = PdfLayoutHelper.renderVirtualPage(
                                renderer,
                                slice,
                                width,
                                height,
                                forPrint = true
                            )
                            renderer.close()
                            pfd.close()

                            PdfLayoutHelper.applySmartDarkThemeInversion(bitmap, darkThemeMode)

                            // Native JBIG1 + QPDL encoding
                            val encodedBytes = SplNativeBridge.nativeEncodeBitmapPage(bitmap, copies, resolutionDpi, useDithering)
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
