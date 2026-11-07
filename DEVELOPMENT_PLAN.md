# Samsung SL-M2070 Direct Wi-Fi Printer App — 개발 플랜 (Development Plan)

> **목표**: ipTIME 공유기 USB 포트(`192.168.0.1:9100`, RAW TCP Socket)에 연결된 호스트 기반 GDI 레이저 프린터 **Samsung SL-M2070**으로 스마트폰에서 PDF 문서를 직접 인쇄하기 위한 경량 Flutter Android 앱 구축.

---

## 1. 기술적 배경 및 핵심 과제 (Technical Challenge)

1. **호스트 기반 GDI 프린터의 한계**:
   - Samsung SL-M2070은 하드웨어 PDF/PostScript/PCL 인터프리터가 없으며 오직 **SPLv2 (Samsung Printer Language v2 / QPDL)** 포맷만 이해합니다.
   - ipTIME 공유기의 USB 프린터 서버 기능은 단순 **RAW TCP Port 9100 포워딩**만 수행하므로, 스마트폰 앱 단에서 완벽한 SPLv2/QPDL 패킷(JBIG1 압축 포함)을 생성해 스트리밍해야 합니다.
2. **메모리 및 성능 병목 해결**:
   - A4 용지 600 DPI 기준 단일 페이지의 픽셀 해상도는 **$4960 \times 7016$** (약 3,480만 픽셀)입니다.
   - `ARGB_8888` 비트맵으로 렌더링할 경우 페이지당 약 **139.2 MB**의 메모리를 점유하므로, 모바일 환경에서 OOM(Out Of Memory)을 방지하기 위해 **페이지 단위 스트리밍 파이프라인** 또는 **대역(Band) 분할 렌더링 + C++ NDK (JNI/FFI) 직접 메모리 처리**가 필수적입니다.
3. **QPDL Version 2 & JBIG1 (ITU-T T.82) 압축**:
   - SL-M2070은 QPDL v2 (Sub-type `0x13` JBIG1 또는 `0x15` 압축 스트림) 규격을 사용합니다.
   - 순수 Dart로 $4960 \times 7016$ 픽셀에 대해 Floyd-Steinberg 디더링 및 산술 부호화 기반의 JBIG1 압축을 수행하면 속도가 매우 느리므로, 검증된 오픈소스 `jbigkit` (`libjbig`) 및 `splix` / `foo2qpdl` 알고리즘을 **Android NDK (C/C++) + Dart FFI**로 포팅하여 네이티브 속도로 처리합니다.

---

## 2. 전체 시스템 아키텍처 (System Architecture)

```
+-----------------------------------------------------------------------+
|                        Flutter UI Layer (Dart)                        |
|  - PDF File Picker & Android ACTION_SEND / ACTION_VIEW Intent Handler |
|  - Interactive PDF Preview & Print Config (IP, Port, Copies, Dither)  |
|  - Live Progress State (Rendering -> Encoding -> Sending -> Done)     |
|  - In-App Real-time Execution Console / Logger Sheet                  |
+-----------------------------------+-----------------------------------+
                                    |
                    Platform Channel / Dart FFI
                                    v
+-----------------------------------------------------------------------+
|                 Native Processing Pipeline (Android / NDK)            |
|                                                                       |
|  1. PDF Rasterizer (Kotlin / Android PdfRenderer)                     |
|     - Renders PDF Page -> 4960 x 7016 Bitmap (White background)       |
|                                                                       |
|  2. 1-Bit Halftoning & Bit-Packer (C++ NDK / JNI)                     |
|     - Grayscale Luminance conversion                                  |
|     - Thresholding (Text mode) or Floyd-Steinberg Dithering (Photo)   |
|     - 8 pixels/byte MSB-first packing (620 bytes per scanline)        |
|                                                                       |
|  3. SPLv2 / QPDL & JBIG1 Encoder (C++ NDK + jbigkit)                  |
|     - PJL Job Header (@PJL ENTER LANGUAGE = QPDL)                     |
|     - QPDL Page Header (0x0900, A4, 600 DPI, Simplex, Copies)         |
|     - Band Partitioning (128 lines/band) + JBIG1 BIE/BID Compression  |
|     - QPDL Page Footer & @PJL EOJ                                     |
+-----------------------------------+-----------------------------------+
                                    |
                         Encoded SPL Byte Stream
                                    v
+-----------------------------------------------------------------------+
|                    Network Socket Client (Dart IO)                    |
|  - Raw TCP Socket (192.168.0.1:9100, Timeout: 10s)                    |
|  - 32 KB Chunked Streaming + Flush + Graceful Close                   |
+-----------------------------------------------------------------------+
```

---

## 3. 프로젝트 디렉터리 구조 (Directory Structure)

기본 프로젝트 경로: `D:\My Documents\AI\samsung_m2070_printer`

```text
samsung_m2070_printer/
├── android/
│   └── app/
│       └── src/main/
│           ├── AndroidManifest.xml          # 네트워크 권한 및 PDF Intent Filter
│           ├── kotlin/.../MainActivity.kt   # PdfRenderer 및 Intent 수신 브릿지
│           └── cpp/                         # C++ NDK (SPLv2 + JBIG1 인코더)
│               ├── CMakeLists.txt
│               ├── jbig/                    # jbigkit (jbig.c, jbig.h, jbig_ar.c, jbig_ar.h)
│               ├── image_halftone.cpp       # Grayscale -> 1-bit Dithering / Thresholding
│               ├── qpdl_encoder.cpp         # SPLv2 / QPDL 패킷 및 밴드 헤더 생성기
│               └── native_bridge.cpp        # JNI / Dart FFI 인터페이스
├── lib/
│   ├── main.dart                            # 앱 엔트리포인트 및 테마 설정
│   ├── models/
│   │   ├── print_config.dart                # IP, Port, 용지크기, 매수, 하프토닝 모드 설정 모델
│   │   └── print_job_state.dart             # 진행 상태(Rendering/Encoding/Sending/Done) 및 로그 모델
│   ├── services/
│   │   ├── intent_service.dart              # 외부 앱 PDF 공유(Share/Open) 수신 서비스
│   │   ├── pdf_render_service.dart          # Android PdfRenderer 호출 및 프리뷰/렌더링 제어
│   │   ├── spl_encoder_service.dart         # 네이티브 QPDL/JBIG1 인코더 호출 및 순수 Dart 헤더 빌더
│   │   ├── raw_socket_client.dart           # TCP 9100 32KB 청크 스트리밍 클라이언트
│   │   └── print_logger.dart                # 인앱 콘솔 로거 (Stream/ChangeNotifier)
│   └── ui/
│       ├── home_screen.dart                 # 메인 화면 (설정 패널 + 프리뷰 + 프린트 버튼)
│       └── widgets/
│           ├── config_panel.dart            # IP(192.168.0.1), Port(9100), Copies 설정 UI
│           ├── pdf_preview_card.dart        # 인터랙티브 페이지 프리뷰어
│           ├── print_progress_sheet.dart    # 단계별 실시간 진행률 표시
│           └── console_log_sheet.dart       # 소켓 타임아웃, 페이로드 크기, 에러 추적 콘솔창
├── test/
│   ├── qpdl_header_test.dart                # PJL 및 QPDL 헤더/푸터 매직 바이트 단위 테스트
│   ├── bit_packing_test.dart                # 1-bit MSB 패킹 및 해상도 규격 검증 테스트
│   └── socket_streaming_test.dart           # Mock TCP Server 기반 32KB 청크 전송 테스트
└── pubspec.yaml
```

---

## 4. 핵심 모듈별 상세 설계 (Detailed Technical Design)

### 4.1. UI 및 워크플로우 (UI & Workflow)
1. **PDF 파일 입력**:
   - **내부 선택**: `file_picker`를 이용해 로컬 저장소의 PDF 파일 선택.
   - **외부 앱 연동 (`Intent Filter`)**: 카카오톡, 브라우저, 파일 관리자 등에서 PDF 파일을 "공유(Send to)" 또는 "연결 프로그램(Open with)"으로 열었을 때 즉시 앱이 실행되며 해당 PDF를 로드.
2. **프린터 설정 패널**:
   - **Target IP**: 기본값 `192.168.0.1` (`SharedPreferences`로 마지막 입력값 자동 저장).
   - **Port**: 기본값 `9100`.
   - **Paper Size**: `A4` 고정 (추후 Letter 등 확장 가능 구조).
   - **Copies**: 기본값 `1` (1~99매).
   - **Halftone Mode**: `Text (Threshold)` (문서 인쇄 시 선명한 가독성) / `Photo (Floyd-Steinberg Dithering)` (이미지 포함 문서용) 선택 토글.
3. **인앱 실행 로거 (Console Sheet)**:
   - 타임스탬프 기반 로그 기록: PDF 로드 정보, 페이지별 렌더링 소요 시간(ms), JBIG1 압축 전/후 바이트 크기 및 압축률(%), TCP 소켓 연결 상태, 32KB 청크 전송 진행률, 에러 스택 트레이스 표시 및 클립보드 복사 기능.

---

### 4.2. PDF 렌더링 및 1-Bit 하프토닝 엔진 (PDF Rendering & Halftoning)
1. **정밀 A4 @ 600 DPI 규격**:
   - 폭(Width): $8.27\text{ inch} \times 600\text{ DPI} = \mathbf{4960\text{ px}}$ ($4960 \div 8 = \mathbf{620\text{ bytes/line}}$, 32-bit/64-bit 워드 정렬 일치)
   - 높이(Height): $11.69\text{ inch} \times 600\text{ DPI} = \mathbf{7016\text{ px}}$
   - 1-Bit 비압축 프레임 버퍼 크기: $620 \times 7016 = \mathbf{4,349,920\text{ bytes}}$ ($\approx 4.15\text{ MB/page}$)
2. **메모리 최적화 렌더링**:
   - Android 네이티브 `android.graphics.pdf.PdfRenderer`를 사용하여 한 번에 **1개 페이지씩** 처리 후 즉시 비트맵을 해제(`recycle()`)합니다.
   - 투명 배경 PDF가 검게 출력되는 현상을 막기 위해 비트맵 생성 직후 반드시 `Color.WHITE`(`0xFFFFFFFF`)로 캔버스를 초기화한 뒤 `Page.RENDER_MODE_FOR_PRINT` 옵션으로 렌더링합니다.
3. **1-Bit 패킹 및 디더링 (C++ NDK)**:
   - Android `Bitmap`의 픽셀 버퍼(`AndroidBitmap_lockPixels`)를 C++에서 직접 읽어 $R, G, B$ 값을 그레이스케일 휘도($Y = 0.299R + 0.587G + 0.114B$)로 변환합니다.
   - **프린터 토너 비트 극성**: 백지(White) = `0`, 토너 인쇄(Black) = `1` (8 pixels/byte, **MSB first**).
   - **Floyd-Steinberg Dithering**:
     - 현재 픽셀의 양자화 오차($e$)를 우측($\frac{7}{16}$), 좌하단($\frac{3}{16}$), 하단($\frac{5}{16}$), 우하단($\frac{1}{16}$) 픽셀로 확산하여 2단계(1-bit)로도 자연스러운 음영을 표현합니다.

---

### 4.3. SPLv2 / QPDL 프로토콜 및 JBIG1 인코더 (Protocol Specification)

`splix` (`src/qpdl.cpp`) 및 `foo2qpdl` 오픈소스 리버스 엔지니어링 규격에 기반한 패킷 구조입니다.

#### (1) Job Start Header (PJL Wrapper)
```text
\x1B%-12345X@PJL DEFAULT SERVICEDATE=20261107\r\n
@PJL SET USERNAME="Android"\r\n
@PJL SET JOBNAME="Document.pdf"\r\n
@PJL SET PAPERTYPE = OFF\r\n
@PJL ENTER LANGUAGE = QPDL\r\n
```

#### (2) QPDL Page Start Header (`Record Type 0x00`)
매 페이지 시작 시 `0x09` 매직 바이트로 시작하는 17바이트 헤더를 전송합니다:
| 오프셋 | 크기 | 값 (Hex) | 설명 |
| :--- | :--- | :--- | :--- |
| `0` | 1B | `0x09` | QPDL Signature Magic Byte |
| `1` | 1B | `0x00` | Record Type: Page Header |
| `2` | 1B | `0x02` | QPDL Version (`2` for SL-M2070) |
| `3` | 1B | `0x06` | Vertical Resolution (`6` = 600 DPI) |
| `4..5` | 2B | `0x00, 0x01` | Copies (Big-Endian `uint16`, 예: 1매) |
| `6` | 1B | `0x00` | Paper Type (`0` = A4) |
| `7..8` | 2B | `0x13, 0x60` | Paper Width (4960 px, Big-Endian) |
| `9..10`| 2B | `0x1B, 0x68` | Paper Height (7016 px, Big-Endian) |
| `11` | 1B | `0x00` | Paper Source (`0` = Auto) |
| `12` | 1B | `0x00` | Unknown / Reserved (`0x00`) |
| `13` | 1B | `0x00` | Duplex (`0` = Simplex) |
| `14` | 1B | `0x00` | Tumble (`0` = Off) |
| `15` | 1B | `0x00` | Unknown / Reserved (`0x00`) |
| `16` | 1B | `0x06` | Horizontal Resolution (`6` = 600 DPI) |

#### (3) Band / Plane Data (`Record Type 0x0C` & Compression `0x13` / `0x15`)
- **JBIG1 압축 (권장, Compression Type `0x13` 또는 Multi-band `0x15`)**:
  - `libjbig` (`jbg_enc_init`, `jbg_enc_options`)을 사용하여 1-bit 비트맵을 ITU-T T.82 (JBIG1) 포맷으로 압축합니다.
  - 옵션 설정: `DL = 0`, `D = 0`, `P = 1` (1 bitplane), `YD = 7016`, `XD = 4960`, `L0 = 128` (Band height 128 lines), `MX = 0`, `order = JBG_ILEAVE | JBG_SMID`, `options = JBG_TPBON | JBG_DELAY_AT`.
  - 생성된 20바이트 **BIH (Bi-level Image Header)**는 첫 번째 밴드(`Band 0`) 패킷에 포함하고, 이후 **BID (Bi-level Image Data)** 스트림을 밴드 단위로 QPDL `0x09 0x0C` 레코드 헤더와 체크섬(`uint32` 바이트 합계)으로 감싸서 출력합니다.

#### (4) Page End (`Record Type 0x01`) & Job End Footer
- **Page End Packet**:
  - `0x09` (Magic), `0x01` (Page End Record), `0x00, 0x01` (Copies `uint16` BE) -> 총 4바이트.
- **Job End Packet**:
  - `0x09, 0x09` (QPDL Job End Record)
  - `\x1B%-12345X@PJL EOJ\r\n\x1B%-12345X`

---

### 4.4. 네트워크 소켓 클라이언트 (Network Socket Client)
1. **연결 및 타임아웃**:
   - `Socket.connect(ip, port, timeout: const Duration(seconds: 10))` 사용.
   - `socket.setOption(SocketOption.tcpNoDelay, true)` 설정.
2. **32KB 청크 스트리밍**:
   - 생성된 SPL 바이너리 버퍼를 `32,768 bytes` (32KB) 단위로 슬라이싱하여 전송합니다.
   - 매 청크 또는 일정 주기마다 `await socket.flush()`를 호출하여 ipTIME 공유기의 USB 프린터 스풀 버퍼 오버플로우를 방지하고 UI 진행률(`sentBytes / totalBytes`)을 실시간 업데이트합니다.
3. **예외 처리 및 진단**:
   - `SocketException` (라우터 연결 불가, Wi-Fi 미연결, 포트 닫힘), `TimeoutException` (프린터 전원 꺼짐 또는 USB 케이블 분리로 인한 ACK 지연) 발생 시 즉각 사용자 친화적 메시지 및 콘솔 상세 로그를 출력합니다.

---

## 5. 단계별 구현 로드맵 (Implementation Phases)

### Phase 1: 프로젝트 초기화 및 Android 네이티브 설정
- Flutter 프로젝트 생성 (`samsung_m2070_printer`).
- `AndroidManifest.xml` 설정:
  - `<uses-permission android:name="android.permission.INTERNET" />`
  - `<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />`
  - `application/pdf`에 대한 `ACTION_VIEW` 및 `ACTION_SEND` 인텐트 필터 등록.
- CMake 및 Android NDK 빌드 환경 구성 (`CMakeLists.txt`).

### Phase 2: C++ NDK (Halftoning + JBIG1 + QPDL Encoder) 구현
- `jbigkit` 핵심 소스(`jbig.c`, `jbig_ar.c`) 내장 및 CMake 정적 링크.
- Grayscale 변환, Threshold / Floyd-Steinberg Dithering, 1-bit MSB 패킹 C++ 함수 작성.
- QPDL v2 헤더/밴드/체크섬/푸터 패킷 조립기(`qpdl_encoder.cpp`) 작성 및 JNI/FFI 바인딩.

### Phase 3: PDF 렌더링 브릿지 구현
- Kotlin `PdfRenderer`를 통해 선택된 PDF의 페이지 수 조회, 프리뷰용 저해상도 이미지 생성, 인쇄용 $4960 \times 7016$ 고해상도 비트맵 렌더링 구현.
- 렌더링된 Bitmap을 메모리 복사 없이 네이티브 C++ `AndroidBitmap_lockPixels`로 즉시 전달하여 SPL 패킷으로 변환.

### Phase 4: TCP 9100 소켓 스트리밍 및 UI 연동
- `RawSocketClient` 구현 (10초 타임아웃, 32KB 청크 전송, 취소 토큰 지원).
- 메인 UI 구성:
  - 상단: 파일 선택 / 공유받은 PDF 파일명 표시.
  - 중단: 인터랙티브 PDF 페이지 프리뷰 + 프린터 설정 카드 (IP `192.168.0.1`, Port `9100`, A4, 매수, 디더링 옵션).
  - 하단: 단계별 프로그레스 바 (`Rendering` -> `Encoding SPL` -> `Sending Bytes` -> `Done`), 프린트 실행 버튼, 접이식 인앱 콘솔 로그 시트.

### Phase 5: 단위 테스트 및 검증 (Unit Testing & Verification)
- **SPL 패킷 생성 단위 테스트 (`test/qpdl_header_test.dart`)**:
  - PJL 헤더/푸터 문자열 검증.
  - QPDL Page Header (17 bytes)의 매직 바이트(`0x09 0x00 0x02`), 해상도(`600 DPI`), A4 픽셀 크기(`4960x7016`), 매수 인코딩 검증.
  - 밴드 체크섬 계산 로직 및 JBIG1 BIH/BID 출력 무결성 검증.
- **소켓 스트리밍 테스트 (`test/socket_streaming_test.dart`)**:
  - 로컬 루프백(`127.0.0.1`)에 임시 `ServerSocket`을 띄워 32KB 단위 청크 전송, 총 수신 바이트 일치 여부, 타임아웃/연결 리셋 에러 핸들링을 자동 검증.

---

## 6. 리스크 관리 및 폴백 전략 (Risk Mitigation)

1. **펌웨어별 QPDL 서브타입 차이 대응**:
   - SL-M2070 일부 펌웨어 리비전에서 단일 스트림 JBIG1(`0x13`)과 밴드 분할 JBIG1(`0x15`) 중 특정 방식을 선호할 수 있으므로, 설정 패널의 고급(Advanced) 옵션에서 **Compression Mode (`0x13 Single-band JBIG1` / `0x15 Banded JBIG1`)**를 스위치할 수 있도록 설계합니다.
2. **저사양 기기 메모리 보호**:
   - 50페이지 이상의 대용량 PDF 인쇄 시 전체 페이지를 한꺼번에 메모리에 올리지 않고, **Page $N$ 렌더링 $\rightarrow$ SPL 인코딩 $\rightarrow$ TCP 소켓 스트리밍 $\rightarrow$ 메모리 해제**를 페이지별로 순차 실행하여 메모리 사용량을 항상 일정하게(약 25MB 이하) 유지합니다.
