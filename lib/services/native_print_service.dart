import 'package:flutter/services.dart';
import 'print_logger.dart';

class NativePrintService {
  static const MethodChannel _channel = MethodChannel('com.antigravity/samsung_m2070');

  static Future<String?> getInitialPdfPath() async {
    try {
      final String? path = await _channel.invokeMethod<String>('getInitialPdfPath');
      return path;
    } on PlatformException catch (e) {
      PrintLogger.instance.error("Failed to get initial PDF path: ${e.message}");
      return null;
    }
  }

  static Future<int> getPdfPageCount(String filePath) async {
    try {
      final int count = await _channel.invokeMethod<int>('getPdfPageCount', {'filePath': filePath}) ?? 0;
      return count;
    } on PlatformException catch (e) {
      PrintLogger.instance.error("Failed to get page count: ${e.message}");
      rethrow;
    }
  }

  static Future<Uint8List> renderPagePreview(String filePath, int pageIndex, {int width = 595, int height = 842}) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>('renderPagePreview', {
        'filePath': filePath,
        'pageIndex': pageIndex,
        'width': width,
        'height': height,
      });
      return bytes ?? Uint8List(0);
    } on PlatformException catch (e) {
      PrintLogger.instance.error("Failed to render page preview: ${e.message}");
      rethrow;
    }
  }

  static Future<Uint8List> getJobStartHeader(String jobName) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>('getJobStartHeader', {
        'jobName': jobName,
      });
      return bytes ?? Uint8List(0);
    } on PlatformException catch (e) {
      PrintLogger.instance.error("Failed to get job start header: ${e.message}");
      rethrow;
    }
  }

  static Future<Uint8List> getJobEndFooter() async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>('getJobEndFooter');
      return bytes ?? Uint8List(0);
    } on PlatformException catch (e) {
      PrintLogger.instance.error("Failed to get job end footer: ${e.message}");
      rethrow;
    }
  }

  static Future<Uint8List> renderAndEncodePage({
    required String filePath,
    required int pageIndex,
    required int copies,
    required int resolutionDpi,
    required bool useDithering,
  }) async {
    try {
      final Uint8List? bytes = await _channel.invokeMethod<Uint8List>('renderAndEncodePage', {
        'filePath': filePath,
        'pageIndex': pageIndex,
        'copies': copies,
        'resolutionDpi': resolutionDpi,
        'useDithering': useDithering,
      });
      return bytes ?? Uint8List(0);
    } on PlatformException catch (e) {
      PrintLogger.instance.error("Failed to render and encode page $pageIndex: ${e.message}");
      rethrow;
    }
  }
}
