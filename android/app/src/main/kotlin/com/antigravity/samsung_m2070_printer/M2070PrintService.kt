package com.antigravity.samsung_m2070_printer

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.pdf.PdfRenderer
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.print.PrintAttributes
import android.print.PrinterCapabilitiesInfo
import android.print.PrinterId
import android.print.PrinterInfo
import android.printservice.PrintJob
import android.printservice.PrintService
import android.printservice.PrinterDiscoverySession
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors

class M2070PrintService : PrintService() {
    private val executor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onCreatePrinterDiscoverySession(): PrinterDiscoverySession {
        return object : PrinterDiscoverySession() {
            override fun onStartPrinterDiscovery(priorityList: MutableList<PrinterId>) {
                val printerId = generatePrinterId("samsung_m2070_iptime")
                val capabilities = PrinterCapabilitiesInfo.Builder(printerId)
                    .addMediaSize(PrintAttributes.MediaSize.ISO_A4, true)
                    .addResolution(PrintAttributes.Resolution("600dpi", "600 DPI", 600, 600), true)
                    .addResolution(PrintAttributes.Resolution("300dpi", "300 DPI", 300, 300), false)
                    .setColorModes(PrintAttributes.COLOR_MODE_MONOCHROME, PrintAttributes.COLOR_MODE_MONOCHROME)
                    .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                    .build()

                val printerInfo = PrinterInfo.Builder(
                    printerId,
                    "Samsung M2070 (ipTIME Printer)",
                    PrinterInfo.STATUS_IDLE
                ).setCapabilities(capabilities)
                 .setDescription("http://192.168.0.1:631/printers/ipTIME_Printer")
                 .build()

                addPrinters(listOf(printerInfo))
            }

            override fun onStopPrinterDiscovery() {}
            override fun onValidatePrinters(printerIds: MutableList<PrinterId>) {}
            override fun onStartPrinterStateTracking(printerId: PrinterId) {}
            override fun onStopPrinterStateTracking(printerId: PrinterId) {}
            override fun onDestroy() {}
        }
    }

    override fun onRequestCancelPrintJob(printJob: PrintJob) {
        printJob.cancel()
    }

    override fun onPrintJobQueued(printJob: PrintJob) {
        if (printJob.isQueued) {
            printJob.start()
        }

        val document = printJob.document
        val dataPfd: ParcelFileDescriptor? = document.data
        if (dataPfd == null) {
            printJob.fail("인쇄 문서 데이터를 읽을 수 없습니다.")
            return
        }

        val jobName = printJob.info.label?.ifEmpty { "Document.pdf" } ?: "Document.pdf"
        val copies = printJob.info.copies.coerceAtLeast(1)
        val dpi = printJob.info.attributes.resolution?.horizontalDpi ?: 600

        // Flutter SharedPreferences에서 사용자가 설정한 IP/Port/Path 읽기 (없으면 기본값 사용)
        val prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val host = prefs.getString("flutter.target_ip", "192.168.0.1") ?: "192.168.0.1"
        val port = prefs.getLong("flutter.target_port", 631L).toInt()
        val path = prefs.getString("flutter.target_path", "/printers/ipTIME_Printer") ?: "/printers/ipTIME_Printer"

        // ParcelFileDescriptor를 안전한 임시 파일로 복사 (PdfRenderer는 seek 가능한 FD 필요)
        val tempPdf = File(cacheDir, "spool_${System.currentTimeMillis()}.pdf")
        try {
            FileInputStream(dataPfd.fileDescriptor).use { input ->
                FileOutputStream(tempPdf).use { output ->
                    input.copyTo(output)
                }
            }
            dataPfd.close()
        } catch (e: Exception) {
            printJob.fail("임시 PDF 생성 실패: ${e.message}")
            return
        }

        executor.execute {
            try {
                val pfd = ParcelFileDescriptor.open(tempPdf, ParcelFileDescriptor.MODE_READ_ONLY)
                val renderer = PdfRenderer(pfd)
                val slices = PdfLayoutHelper.buildVirtualPageList(renderer)
                val totalVirtualPages = slices.size

                val width = if (dpi == 300) 2480 else 4960
                val height = if (dpi == 300) 3508 else 7016

                val splPackets = mutableListOf<ByteArray>()
                splPackets.add(SplNativeBridge.nativeGetJobStartHeader(jobName))

                for (i in 0 until totalVirtualPages) {
                    val slice = slices[i]
                    val bitmap = PdfLayoutHelper.renderVirtualPage(
                        renderer,
                        slice,
                        width,
                        height,
                        forPrint = true
                    )
                    // PrintService에서도 다크 모드 문서 스마트 자동 반전 (토너 절약)
                    PdfLayoutHelper.applySmartDarkThemeInversion(bitmap, "auto")

                    val encoded = SplNativeBridge.nativeEncodeBitmapPage(bitmap, copies, dpi, true)
                    bitmap.recycle()

                    if (encoded == null) {
                        throw RuntimeException("페이지 ${i + 1} SPL 인코딩 실패")
                    }
                    splPackets.add(encoded)
                }

                renderer.close()
                pfd.close()
                splPackets.add(SplNativeBridge.nativeGetJobEndFooter())

                // IPP 1.1 헤더 생성 및 TCP 631 전송
                sendIppJob(host, port, path, jobName, copies, splPackets)

                mainHandler.post { printJob.complete() }
            } catch (e: Exception) {
                e.printStackTrace()
                mainHandler.post { printJob.fail("인쇄 오류: ${e.message}") }
            } finally {
                tempPdf.delete()
            }
        }
    }

    private fun sendIppJob(
        host: String,
        port: Int,
        path: String,
        jobName: String,
        copies: Int,
        splPackets: List<ByteArray>
    ) {
        val printerUri = "http://$host:$port$path"
        val ippHeader = buildIppHeader(printerUri, jobName, copies)
        val totalPayloadBytes = ippHeader.size + splPackets.sumOf { it.size }

        Socket().use { socket ->
            socket.connect(InetSocketAddress(host, port), 15000)
            socket.tcpNoDelay = true
            val out = socket.getOutputStream()

            val httpHeaders = "POST $path HTTP/1.1\r\n" +
                    "Host: $host:$port\r\n" +
                    "User-Agent: IPP/2.0\r\n" +
                    "Content-Type: application/ipp\r\n" +
                    "Content-Length: $totalPayloadBytes\r\n" +
                    "Connection: close\r\n\r\n"

            out.write(httpHeaders.toByteArray(Charsets.US_ASCII))
            out.write(ippHeader)
            out.flush()

            val chunkSize = 32 * 1024
            for (packet in splPackets) {
                var offset = 0
                while (offset < packet.size) {
                    val len = minOf(chunkSize, packet.size - offset)
                    out.write(packet, offset, len)
                    out.flush()
                    offset += len
                }
            }

            // 서버 응답 대기 후 종료
            val input = socket.getInputStream()
            val buf = ByteArray(512)
            input.read(buf)
        }
    }

    private fun buildIppHeader(printerUri: String, jobName: String, copies: Int): ByteArray {
        val out = ByteArrayOutputStream()
        // Version 1.1 (0x01, 0x01), Operation Print-Job (0x00, 0x02), Request ID 1 (0x00,0x00,0x00,0x01)
        out.write(byteArrayOf(0x01, 0x01, 0x00, 0x02, 0x00, 0x00, 0x00, 0x01))
        out.write(0x01) // Operation Attributes Tag

        fun writeAttr(tag: Int, name: String, value: String) {
            out.write(tag)
            val nBytes = name.toByteArray(Charsets.UTF_8)
            out.write((nBytes.size shr 8) and 0xFF)
            out.write(nBytes.size and 0xFF)
            out.write(nBytes)
            val vBytes = value.toByteArray(Charsets.UTF_8)
            out.write((vBytes.size shr 8) and 0xFF)
            out.write(vBytes.size and 0xFF)
            out.write(vBytes)
        }

        writeAttr(0x47, "attributes-charset", "utf-8")
        writeAttr(0x48, "attributes-natural-language", "en")
        writeAttr(0x45, "printer-uri", printerUri)
        writeAttr(0x42, "job-name", jobName)
        writeAttr(0x49, "document-format", "application/octet-stream")

        if (copies > 1) {
            out.write(0x02) // Job Attributes Tag
            out.write(0x21) // Integer Tag
            val nBytes = "copies".toByteArray(Charsets.UTF_8)
            out.write((nBytes.size shr 8) and 0xFF)
            out.write(nBytes.size and 0xFF)
            out.write(nBytes)
            out.write(byteArrayOf(0x00, 0x04))
            out.write(
                byteArrayOf(
                    ((copies shr 24) and 0xFF).toByte(),
                    ((copies shr 16) and 0xFF).toByte(),
                    ((copies shr 8) and 0xFF).toByte(),
                    (copies and 0xFF).toByte()
                )
            )
        }

        out.write(0x03) // End of Attributes Tag
        return out.toByteArray()
    }
}
