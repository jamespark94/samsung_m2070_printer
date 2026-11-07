package com.antigravity.samsung_m2070_printer

import android.graphics.Bitmap

object SplNativeBridge {
    init {
        System.loadLibrary("spl_encoder")
    }

    external fun nativeGetJobStartHeader(jobName: String): ByteArray
    external fun nativeGetJobEndFooter(): ByteArray
    external fun nativeEncodeBitmapPage(
        bitmap: Bitmap,
        copies: Int,
        resolutionDpi: Int,
        useDithering: Boolean
    ): ByteArray?
}
