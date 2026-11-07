package com.antigravity.samsung_m2070_printer

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Matrix
import android.graphics.Rect
import android.graphics.pdf.PdfRenderer
import kotlin.math.ceil

data class VirtualPageSlice(
    val pdfPageIndex: Int,
    val sliceIndex: Int,
    val totalSlices: Int
)

object PdfLayoutHelper {
    // A4 ratio: 7016 / 4960 ≈ 1.4145
    private const val A4_ASPECT = 7016f / 4960f

    /**
     * 원본 PDF 페이지들을 검사하여 세로로 긴 원노트 페이지를 가상 다중 페이지로 자동 분할합니다.
     */
    fun buildVirtualPageList(renderer: PdfRenderer): List<VirtualPageSlice> {
        val slices = mutableListOf<VirtualPageSlice>()
        for (i in 0 until renderer.pageCount) {
            val page = renderer.openPage(i)
            val w = page.width.toFloat().coerceAtLeast(1f)
            val h = page.height.toFloat().coerceAtLeast(1f)
            page.close()

            val pageAspect = h / w
            // A4 비율보다 10% 이상 긴 경우 가상 페이지 슬라이싱
            val sliceCount = if (pageAspect > A4_ASPECT * 1.10f) {
                ceil(pageAspect / A4_ASPECT).toInt().coerceAtLeast(1)
            } else {
                1
            }

            for (s in 0 until sliceCount) {
                slices.add(VirtualPageSlice(pdfPageIndex = i, sliceIndex = s, totalSlices = sliceCount))
            }
        }
        return slices
    }

    /**
     * 가상 페이지 슬라이스를 A4 비트맵에 등비율(Matrix)로 렌더링합니다.
     */
    fun renderVirtualPage(
        renderer: PdfRenderer,
        slice: VirtualPageSlice,
        targetWidth: Int,
        targetHeight: Int,
        forPrint: Boolean
    ): Bitmap {
        val page = renderer.openPage(slice.pdfPageIndex)
        val bitmap = Bitmap.createBitmap(targetWidth, targetHeight, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.WHITE)

        val marginX = targetWidth * 0.03f
        val marginY = targetHeight * 0.03f
        val printableW = targetWidth - (marginX * 2)
        val printableH = targetHeight - (marginY * 2)

        val scale = if (slice.totalSlices == 1) {
            minOf(printableW / page.width.toFloat(), printableH / page.height.toFloat())
        } else {
            printableW / page.width.toFloat()
        }

        val translateX = if (slice.totalSlices == 1) {
            // 중앙 정렬
            marginX + (printableW - page.width * scale) / 2f
        } else {
            marginX
        }
        val translateY = marginY - (slice.sliceIndex * printableH)

        val matrix = Matrix().apply {
            setScale(scale, scale)
            postTranslate(translateX, translateY)
        }

        val clipRect = Rect(
            marginX.toInt(),
            marginY.toInt(),
            (targetWidth - marginX).toInt(),
            (targetHeight - marginY).toInt()
        )

        val mode = if (forPrint) PdfRenderer.Page.RENDER_MODE_FOR_PRINT else PdfRenderer.Page.RENDER_MODE_FOR_DISPLAY
        page.render(bitmap, clipRect, matrix, mode)
        page.close()

        return bitmap
    }

    /**
     * 다크 모드 배경을 자동 감지하여 흰 배경 + 선명한 검은 글씨로 스마트 반전 (토너 절약)
     * darkThemeMode: "auto", "always", "off"
     */
    fun applySmartDarkThemeInversion(bitmap: Bitmap, darkThemeMode: String = "auto") {
        if (darkThemeMode == "off") return

        val width = bitmap.width
        val height = bitmap.height
        val pixels = IntArray(width * height)
        bitmap.getPixels(pixels, 0, width, 0, 0, width, height)

        if (darkThemeMode == "auto") {
            var darkCount = 0
            var sampleCount = 0
            val step = maxOf(1, (width * height) / 10000)
            for (i in pixels.indices step step) {
                val c = pixels[i]
                val lum = ((Color.red(c) * 77) + (Color.green(c) * 150) + (Color.blue(c) * 29)) shr 8
                if (lum < 85) darkCount++
                sampleCount++
            }
            if (darkCount * 2 < sampleCount) {
                // 밝은 배경 문서 -> 반전 불필요
                return
            }
        }

        // 반전 처리 및 순백색 클리핑
        for (i in pixels.indices) {
            val c = pixels[i]
            val r = 255 - Color.red(c)
            val g = 255 - Color.green(c)
            val b = 255 - Color.blue(c)
            val invLum = ((r * 77) + (g * 150) + (b * 29)) shr 8

            if (invLum >= 190) {
                pixels[i] = Color.WHITE
            } else {
                val darkened = (invLum * 0.7f).toInt().coerceIn(0, 255)
                pixels[i] = Color.rgb(darkened, darkened, darkened)
            }
        }
        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }
}
