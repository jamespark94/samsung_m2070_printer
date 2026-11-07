import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/print_config.dart';
import '../models/print_job_state.dart';
import '../services/ipp_packet_builder.dart';
import '../services/ipp_print_client.dart';
import '../services/native_print_service.dart';
import '../services/print_logger.dart';
import '../services/raw_socket_client.dart';
import 'widgets/config_panel.dart';
import 'widgets/console_log_sheet.dart';
import 'widgets/pdf_preview_card.dart';
import 'widgets/print_progress_sheet.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  PrintConfig _config = const PrintConfig();
  PrintJobProgress _progress = const PrintJobProgress();
  final RawSocketClient _rawSocketClient = RawSocketClient();
  final IppPrintClient _ippClient = IppPrintClient();

  String? _pdfFilePath;
  String? _pdfFileName;
  int _totalPages = 0;
  int _previewPageIndex = 0;
  Uint8List? _previewImageBytes;
  bool _isPreviewLoading = false;
  bool _isPrinting = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConfig();
    _checkInitialIntentPdf();
  }

  Future<void> _loadSavedConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('target_ip');
    final savedPort = prefs.getInt('target_port');
    final savedPath = prefs.getString('target_path');
    final savedProtoIndex = prefs.getInt('target_protocol');

    if (savedIp != null || savedPort != null || savedPath != null || savedProtoIndex != null) {
      setState(() {
        _config = _config.copyWith(
          ip: savedIp ?? _config.ip,
          port: savedPort ?? _config.port,
          printerPath: savedPath ?? _config.printerPath,
          protocol: savedProtoIndex != null ? ConnectionProtocol.values[savedProtoIndex] : _config.protocol,
        );
      });
    }
  }

  Future<void> _saveConfig(PrintConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('target_ip', config.ip);
    await prefs.setInt('target_port', config.port);
    await prefs.setString('target_path', config.printerPath);
    await prefs.setInt('target_protocol', config.protocol.index);
  }

  Future<void> _checkInitialIntentPdf() async {
    final sharedPath = await NativePrintService.getInitialPdfPath();
    if (sharedPath != null && File(sharedPath).existsSync()) {
      _loadPdf(sharedPath);
    }
  }

  Future<void> _pickPdfFile() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (files.isNotEmpty && files.first.path != null) {
      await _loadPdf(files.first.path!);
    }
  }

  Future<void> _loadPdf(String path) async {
    try {
      setState(() {
        _pdfFilePath = path;
        _pdfFileName = path.split(Platform.pathSeparator).last;
        _previewPageIndex = 0;
        _previewImageBytes = null;
        _isPreviewLoading = true;
      });

      PrintLogger.instance.info("PDF 로드: $_pdfFileName");
      final pages = await NativePrintService.getPdfPageCount(path);
      setState(() {
        _totalPages = pages;
      });
      PrintLogger.instance.info("총 페이지 수: $pages");

      if (pages > 0) {
        await _loadPreviewPage(0);
      }
    } catch (e) {
      PrintLogger.instance.error("PDF 열기 실패: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("PDF 파일을 열 수 없습니다: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isPreviewLoading = false);
    }
  }

  Future<void> _loadPreviewPage(int pageIndex) async {
    if (_pdfFilePath == null) return;
    setState(() => _isPreviewLoading = true);
    try {
      final bytes = await NativePrintService.renderPagePreview(_pdfFilePath!, pageIndex);
      setState(() {
        _previewPageIndex = pageIndex;
        _previewImageBytes = bytes;
      });
    } catch (e) {
      PrintLogger.instance.error("미리보기 렌더링 실패: $e");
    } finally {
      if (mounted) setState(() => _isPreviewLoading = false);
    }
  }

  Future<void> _startPrint() async {
    if (_pdfFilePath == null || _totalPages == 0 || _isPrinting) return;

    setState(() {
      _isPrinting = true;
      _progress = PrintJobProgress(
        step: PrintStep.rendering,
        currentPage: 0,
        totalPages: _totalPages,
        statusMessage: "인쇄 작업을 준비 중입니다...",
      );
    });

    await _saveConfig(_config);
    PrintLogger.instance.info("인쇄 시작: ${_config.fullUri} (Copies=${_config.copies}, Res=${_config.resolutionDpi}DPI)");

    try {
      // 1. Generate PJL Job Start Header
      final jobStart = await NativePrintService.getJobStartHeader(_pdfFileName ?? "Document.pdf");
      final List<List<int>> packetsToSend = [jobStart];

      // 2. Render and encode each page in sequence
      for (int i = 0; i < _totalPages; i++) {
        setState(() {
          _progress = _progress.copyWith(
            step: PrintStep.rendering,
            currentPage: i,
            statusMessage: "페이지 ${i + 1}/$_totalPages 고해상도 렌더링 중...",
          );
        });

        PrintLogger.instance.info("페이지 ${i + 1}/$_totalPages 렌더링 및 SPL 인코딩 중...");

        setState(() {
          _progress = _progress.copyWith(
            step: PrintStep.encoding,
            statusMessage: "페이지 ${i + 1}/$_totalPages JBIG1 압축 중...",
          );
        });

        final pagePacket = await NativePrintService.renderAndEncodePage(
          filePath: _pdfFilePath!,
          pageIndex: i,
          copies: _config.copies,
          resolutionDpi: _config.resolutionDpi,
          useDithering: _config.halftoneMode == HalftoneMode.dithering,
        );

        packetsToSend.add(pagePacket);
        PrintLogger.instance.info("페이지 ${i + 1} 인코딩 완료 (${(pagePacket.length / 1024).toStringAsFixed(1)} KB)");
      }

      // 3. Generate Job End Footer
      final jobEnd = await NativePrintService.getJobEndFooter();
      packetsToSend.add(jobEnd);

      // 4. Send via IPP (CUPS 631) or RAW TCP (9100)
      if (_config.protocol == ConnectionProtocol.ipp) {
        final ippHeader = IppPacketBuilder.createPrintJobHeader(
          printerUri: "http://${_config.ip}:${_config.port}${_config.printerPath}",
          jobName: _pdfFileName ?? "Document.pdf",
          copies: _config.copies,
        );

        final totalBytes = ippHeader.length + packetsToSend.fold<int>(0, (sum, p) => sum + p.length);
        setState(() {
          _progress = _progress.copyWith(
            step: PrintStep.sending,
            totalBytes: totalBytes,
            sentBytes: 0,
            statusMessage: "ipTIME CUPS 서버(631)로 IPP 전송 중...",
          );
        });

        await _ippClient.printJob(
          host: _config.ip,
          port: _config.port,
          path: _config.printerPath,
          ippHeader: ippHeader,
          splPackets: packetsToSend,
          onProgress: (sent, total) {
            if (mounted) {
              setState(() {
                _progress = _progress.copyWith(
                  sentBytes: sent,
                  totalBytes: total,
                );
              });
            }
          },
        );
      } else {
        // Raw TCP Socket
        final totalBytes = packetsToSend.fold<int>(0, (sum, p) => sum + p.length);
        setState(() {
          _progress = _progress.copyWith(
            step: PrintStep.sending,
            totalBytes: totalBytes,
            sentBytes: 0,
            statusMessage: "RAW TCP 9100으로 전송 중...",
          );
        });

        await _rawSocketClient.sendPayload(
          host: _config.ip,
          port: _config.port,
          bytePackets: packetsToSend,
          onProgress: (sent, total) {
            if (mounted) {
              setState(() {
                _progress = _progress.copyWith(
                  sentBytes: sent,
                  totalBytes: total,
                );
              });
            }
          },
        );
      }

      setState(() {
        _progress = _progress.copyWith(
          step: PrintStep.completed,
          statusMessage: "프린터로 전체 데이터 전송이 성공적으로 완료되었습니다.",
        );
      });
      PrintLogger.instance.info("인쇄 작업 완료!");
    } catch (e) {
      setState(() {
        _progress = _progress.copyWith(
          step: PrintStep.error,
          statusMessage: "인쇄 실패: $e",
        );
      });
      PrintLogger.instance.error("인쇄 중 오류 발생: $e");
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Samsung M2070 Direct Print"),
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: "PDF 파일 선택",
            onPressed: _isPrinting ? null : _pickPdfFile,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 36),
                title: Text(_pdfFileName ?? "선택된 PDF 파일 없음"),
                subtitle: Text(_pdfFilePath != null ? "총 $_totalPages 페이지" : "우측 상단 아이콘 또는 아래 버튼을 눌러 PDF를 선택하세요."),
                trailing: ElevatedButton.icon(
                  icon: const Icon(Icons.folder_open, size: 18),
                  label: const Text("선택"),
                  onPressed: _isPrinting ? null : _pickPdfFile,
                ),
              ),
            ),
            const SizedBox(height: 12),

            ConfigPanel(
              config: _config,
              isPrinting: _isPrinting,
              onChanged: (newConfig) => setState(() => _config = newConfig),
            ),
            const SizedBox(height: 12),

            if (_pdfFilePath != null && _totalPages > 0)
              PdfPreviewCard(
                currentPage: _previewPageIndex,
                totalPages: _totalPages,
                previewImageBytes: _previewImageBytes,
                isLoading: _isPreviewLoading,
                onPageChanged: _loadPreviewPage,
              ),

            PrintProgressSheet(progress: _progress),

            const SizedBox(height: 16),

            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _isPrinting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.print, size: 24),
              label: Text(
                _isPrinting 
                    ? "인쇄 데이터 전송 중..." 
                    : (_config.protocol == ConnectionProtocol.ipp 
                        ? "ipTIME 프린터로 인쇄 (IPP 631)" 
                        : "프린터로 인쇄 (RAW 9100)"),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: (_pdfFilePath != null && !_isPrinting) ? _startPrint : null,
            ),

            const SizedBox(height: 16),

            const ConsoleLogSheet(),
          ],
        ),
      ),
    );
  }
}
