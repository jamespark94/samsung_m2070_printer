# Android 시스템 인쇄 서비스(`PrintService`) 및 외부 앱(OneNote 등) 직접 출력 연동 변경안

> **목적**: 원노트(OneNote), 브라우저, 갤러리 등 외부 앱에서 PDF 파일로 수동 저장·변환하는 과정 없이, **[인쇄]** 또는 **[공유]** 메뉴를 통해 `http://192.168.0.1:631/printers/ipTIME_Printer`로 즉시 출력하도록 앱을 확장하는 설계안입니다.

---

## 1. 현황 분석 및 원인 진단

현재 프로젝트([`samsung_m2070_printer`](file:///D:/My%20Documents/AI/samsung_m2070_printer))의 코드를 분석한 결과, 외부 앱에서 직접 인쇄할 때 다음 **2가지 구조적 병목**이 존재합니다.

1. **시스템 프린터 플러그인(`android.printservice.PrintService`) 미구현**:
   - 안드로이드 앱(원노트, 크롬, 기본 문서 뷰어 등)에서 **[인쇄]** 버튼을 누르면 OS의 기본 인쇄 스풀러가 작동합니다.
   - 이때 스풀러는 기기에 등록된 `PrintService` 목록만 검색하므로, 현재 액티비티(`MainActivity`)만 있는 우리 앱은 프린터 목록에 나타나지 않습니다.
   - `PrintService`를 등록하면 **원노트에서 [인쇄]를 누르는 순간 안드로이드 OS가 원노트 화면을 자동으로 임시 PDF(`ParcelFileDescriptor`)로 변환하여 우리 서비스에 직접 전달**해 줍니다.
2. **앱 실행 중 외부 공유(`onNewIntent`) 수신 시 Flutter UI 미갱신 버그**:
   - 현재 [`AndroidManifest.xml`](file:///D:/My%20Documents/AI/samsung_m2070_printer/android/app/src/main/AndroidManifest.xml#L27-L43)에 `ACTION_SEND` 및 `ACTION_VIEW`(`application/pdf`)가 선언되어 있고, [`MainActivity.kt`](file:///D:/My%20Documents/AI/samsung_m2070_printer/android/app/src/main/kotlin/com/antigravity/samsung_m2070_printer/MainActivity.kt#L46-L70)의 `onNewIntent`에서 `pendingSharedPdfPath`에 경로를 저장하고 있습니다.
   - 하지만 `launchMode="singleTask"` 상태에서 앱이 이미 백그라운드에 켜져 있을 때 원노트에서 [PDF로 공유]를 하면, [`HomeScreen`](file:///D:/My%20Documents/AI/samsung_m2070_printer/lib/ui/home_screen.dart#L39-L44)의 `initState()`는 다시 호출되지 않으므로 새로 공유받은 PDF가 화면에 로드되지 않습니다.

---

## 2. 해결 아키텍처 (2-Track 연동 방안)

외부 앱의 특성에 따라 어떤 경로로든 100% 직접 인쇄가 가능하도록 두 가지 경로를 모두 완성합니다.

```
[원노트 / 크롬 / 일반 앱]
   │
   ├── 경로 A: 앱 내 [인쇄] 메뉴 선택 (추천 · 완전 자동)
   │      ▼
   │   Android OS Print Spooler (화면을 자동으로 PDF 문서 스트림으로 변환)
   │      ▼
   │   M2070PrintService (Kotlin 백그라운드 서비스)
   │      ├─ SharedPreferences에서 설정(IP: 192.168.0.1, Port: 631, Path: /printers/ipTIME_Printer) 로드
   │      ├─ PdfRenderer로 페이지별 Bitmap 렌더링 (4960x7016 @ 600DPI)
   │      ├─ SplNativeBridge (기존 C++ QpdlEncoder) 호출하여 SPLv3/Algo0x11 패킷 생성
   │      └─ Kotlin Socket으로 IPP(631) 또는 RAW(9100) 직접 전송 후 작업 완료 통보! (앱 UI 켤 필요 없음)
   │
   └── 경로 B: 원노트 [페이지 공유 -> PDF로 공유] 선택 (프리뷰 확인 후 인쇄)
          ▼
       MainActivity.onNewIntent()
          ▼
       MethodChannel.invokeMethod("onNewPdfShared", localPath) ──> Flutter HomeScreen 즉시 프리뷰 갱신
```

---

## 3. 파일별 상세 변경안

### 3.1. C++ JNI 브릿지 공용화 (`SplNativeBridge.kt` & `native_bridge.cpp`)
현재 C++ 네이티브 함수가 `MainActivity` 클래스에 종속(`Java_com_antigravity_..._MainActivity_native...`)되어 있어 백그라운드 `PrintService`에서 호출할 수 없습니다. 이를 싱글톤 객체인 `SplNativeBridge`로 분리하여 `MainActivity`와 `M2070PrintService` 양쪽에서 모두 사용할 수 있게 합니다.

#### 📄 [신규] `android/app/src/main/kotlin/com/antigravity/samsung_m2070_printer/SplNativeBridge.kt`
```kotlin
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
```

#### 📄 [수정] `android/app/src/main/cpp/native_bridge.cpp`
JNI 함수 심볼 이름을 `MainActivity`에서 `SplNativeBridge`로 변경(또는 두 심볼 모두 유지)합니다.
```cpp
// 변경 전: Java_com_antigravity_samsung_1m2070_1printer_MainActivity_nativeGetJobStartHeader
// 변경 후:
JNIEXPORT jbyteArray JNICALL
Java_com_antigravity_samsung_1m2070_1printer_SplNativeBridge_nativeGetJobStartHeader(
        JNIEnv* env, jobject /* this */, jstring jobName) { ... }

JNIEXPORT jbyteArray JNICALL
Java_com_antigravity_samsung_1m2070_1printer_SplNativeBridge_nativeGetJobEndFooter(
        JNIEnv* env, jobject /* this */) { ... }

JNIEXPORT jbyteArray JNICALL
Java_com_antigravity_samsung_1m2070_1printer_SplNativeBridge_nativeEncodeBitmapPage(
        JNIEnv* env, jobject /* this */, jobject bitmap, jint copies, jint resolutionDpi, jboolean useDithering) { ... }
```

---

### 3.2. 안드로이드 시스템 `PrintService` 구현 (`M2070PrintService.kt`)
원노트 등 모든 앱의 **[인쇄]** 화면에서 **`Samsung M2070 (ipTIME 631)`** 프린터가 나타나도록 하고, 인쇄 버튼 클릭 시 Flutter 엔진을 띄우지 않고도 네이티브 스레드에서 즉시 렌더링 + SPL 인코딩 + `http://192.168.0.1:631/printers/ipTIME_Printer` 전송까지 처리합니다.

#### 📄 [신규] `android/app/src/main/kotlin/com/antigravity/samsung_m2070_printer/M2070PrintService.kt`
```kotlin
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

        val jobName = printJob.info.label.ifEmpty { "OneNote_Document.pdf" }
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
                val totalPages = renderer.pageCount

                val width = if (dpi == 300) 2480 else 4960
                val height = if (dpi == 300) 3508 else 7016

                val splPackets = mutableListOf<ByteArray>()
                splPackets.add(SplNativeBridge.nativeGetJobStartHeader(jobName))

                for (i in 0 until totalPages) {
                    val page = renderer.openPage(i)
                    val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    val canvas = Canvas(bitmap)
                    canvas.drawColor(Color.WHITE)
                    page.render(bitmap, null, null, PdfRenderer.Page.RENDER_MODE_FOR_PRINT)
                    page.close()

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
```

---

### 3.3. `AndroidManifest.xml` 및 서비스 메타데이터 등록
안드로이드 OS가 우리 앱을 공식 인쇄 서비스로 인식하도록 `<service>` 태그와 설정 XML을 추가합니다.

#### 📄 [신규] `android/app/src/main/res/xml/printservice.xml`
```xml
<?xml version="1.0" encoding="utf-8"?>
<print-service xmlns:android="http://schemas.android.com/apk/res/android"
    android:settingsActivity="com.antigravity.samsung_m2070_printer.MainActivity"
    android:addPrintersActivity="com.antigravity.samsung_m2070_printer.MainActivity"
    android:vendor="Samsung / ipTIME" />
```

#### 📄 [수정] `android/app/src/main/AndroidManifest.xml`
`<application>` 내부(`</activity>` 아래)에 다음 `<service>` 블록을 추가합니다.
```xml
        <!-- Android System PrintService 등록 -->
        <service
            android:name=".M2070PrintService"
            android:label="Samsung M2070 Direct Print"
            android:permission="android.permission.BIND_PRINT_SERVICE"
            android:exported="true">
            <intent-filter>
                <action android:name="android.printservice.PrintService" />
            </intent-filter>
            <meta-data
                android:name="android.printservice"
                android:resource="@xml/printservice" />
        </service>
```

---

### 3.4. 실시간 공유 수신(`onNewIntent`) 브릿지 보완 (`MainActivity.kt` & `home_screen.dart`)
원노트에서 **[페이지 공유 ➔ PDF로 공유]**를 선택했을 때, 앱이 이미 켜져 있는 상태더라도 즉시 새 PDF를 불러오도록 이벤트를 연결합니다.

#### 📄 [수정] `android/app/src/main/kotlin/com/antigravity/samsung_m2070_printer/MainActivity.kt`
`MethodChannel` 인스턴스를 멤버 변수(`private var methodChannel: MethodChannel? = null`)로 보관하고, `handleIntent()`에서 파일 복사 직후 Flutter로 즉시 알림을 보냅니다.
```kotlin
    private var methodChannel: MethodChannel? = null

    private fun handleIntent(intent: Intent?) {
        // ... (기존 URI 추출 로직 동일) ...
        if (uri != null) {
            val localPath = copyUriToInternalStorage(uri)
            if (localPath != null) {
                pendingSharedPdfPath = localPath
                // 앱이 이미 실행 중일 때 Flutter 화면으로 즉시 전달
                methodChannel?.invokeMethod("onSharedPdfReceived", localPath)
            }
        }
    }
```

#### 📄 [수정] `lib/services/native_print_service.dart` 및 `lib/ui/home_screen.dart`
`NativePrintService`에 콜백 리스너를 등록하여 `onSharedPdfReceived` 수신 시 `_loadPdf(path)`가 즉시 호출되도록 합니다.
```dart
// lib/services/native_print_service.dart 추가
static void setSharedPdfListener(void Function(String path) onPdfReceived) {
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'onSharedPdfReceived' && call.arguments is String) {
      final path = call.arguments as String;
      onPdfReceived(path);
    }
  });
}
```
```dart
// lib/ui/home_screen.dart의 initState() 내부에 추가
@override
void initState() {
  super.initState();
  _loadSavedConfig();
  _checkInitialIntentPdf();
  NativePrintService.setSharedPdfListener((sharedPath) {
    if (File(sharedPath).existsSync()) {
      _loadPdf(sharedPath);
    }
  });
}
```

---

## 4. 변경안 적용 후 실제 사용 방법 (원노트 기준)

위 변경안을 적용하여 앱을 빌드/설치한 뒤에는 다음 **2가지 방법**으로 원노트에서 파일 저장 없이 바로 인쇄할 수 있습니다.

### 방법 1: 안드로이드 시스템 `[인쇄]` 메뉴 사용 (원노트 / 브라우저 / 오피스 공통)
1. 최초 1회 확인: 안드로이드 **설정 ➔ 연결 ➔ 기타 연결 설정 ➔ 인쇄** 메뉴에서 **`Samsung M2070 Direct Print`** 서비스가 **켜짐(ON)** 상태인지 확인합니다.
2. 원노트나 문서를 열고 **[인쇄]**(또는 **[공유 ➔ 인쇄]**)를 누릅니다.
3. 상단 프린터 선택 드롭다운에서 **`Samsung M2070 (ipTIME Printer)`**를 선택합니다.
4. 매수(Copies) 선택 후 노란색/파란색 **[인쇄] 아이콘**을 누르면, 백그라운드에서 자동으로 SPL 변환 후 `http://192.168.0.1:631/printers/ipTIME_Printer`로 전송되어 즉시 출력됩니다.

### 방법 2: 원노트 `[공유]` 메뉴 사용 (미리보기 확인 후 출력하고 싶을 때)
1. 안드로이드 원노트 우측 상단 **점 3개(`⋮`) ➔ [페이지 공유] ➔ [PDF로 공유]**를 누릅니다.
2. 안드로이드 하단 공유 시트에서 **`M2070 Direct Print`** 앱 아이콘을 누릅니다.
3. 별도로 파일을 저장할 필요 없이, 즉시 우리 앱이 열리면서 방금 보던 원노트 페이지의 미리보기가 자동으로 뜹니다.
4. 하단의 **[ipTIME 프린터로 인쇄 (IPP 631)]** 버튼을 누르면 출력됩니다.
