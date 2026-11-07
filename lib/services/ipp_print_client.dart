import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'print_logger.dart';

class IppPrintClient {
  static const int chunkSize = 32 * 1024; // 32KB streaming chunk

  /// Streams IPP Print-Job request with SPL payload to http://host:port/path
  Future<void> printJob({
    required String host,
    required int port,
    required String path,
    required Uint8List ippHeader,
    required List<List<int>> splPackets,
    required void Function(int sentBytes, int totalBytes) onProgress,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final logger = PrintLogger.instance;
    final totalPayloadBytes = ippHeader.length + splPackets.fold<int>(0, (sum, p) => sum + p.length);
    final targetUri = "http://$host:$port$path";

    logger.info("Connecting to IPP printer: $targetUri (Total: ${(totalPayloadBytes / 1024).toStringAsFixed(1)} KB)...");

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      logger.info("Connected to $host:$port. Sending HTTP POST request headers...");

      // Construct HTTP 1.1 POST Header with Content-Length
      final httpHeaders = 
          "POST $path HTTP/1.1\r\n"
          "Host: $host:$port\r\n"
          "User-Agent: IPP/2.0\r\n"
          "Content-Type: application/ipp\r\n"
          "Content-Length: $totalPayloadBytes\r\n"
          "Connection: close\r\n"
          "\r\n";

      socket.add(Uint8List.fromList(httpHeaders.codeUnits));
      await socket.flush();

      int sentBytes = 0;

      // 1. Stream IPP Header
      socket.add(ippHeader);
      sentBytes += ippHeader.length;
      onProgress(sentBytes, totalPayloadBytes);
      await socket.flush();

      // 2. Stream SPL Packets in 32KB chunks
      for (final packet in splPackets) {
        int offset = 0;
        while (offset < packet.length) {
          final end = (offset + chunkSize < packet.length) ? offset + chunkSize : packet.length;
          final chunk = (offset == 0 && end == packet.length)
              ? packet
              : packet.sublist(offset, end);

          socket.add(chunk);
          sentBytes += chunk.length;
          offset = end;

          onProgress(sentBytes, totalPayloadBytes);
          await socket.flush();
        }
      }

      logger.info("All bytes sent ($sentBytes/$totalPayloadBytes). Flushing and awaiting HTTP response...");
      await socket.flush();

      // Read response
      final responseCompleter = Completer<List<int>>();
      final receivedData = <int>[];

      socket.listen(
        (data) {
          receivedData.addAll(data);
        },
        onError: (e) {
          if (!responseCompleter.isCompleted) {
            responseCompleter.completeError(e);
          }
        },
        onDone: () {
          if (!responseCompleter.isCompleted) {
            responseCompleter.complete(receivedData);
          }
        },
      );

      final respBytes = await responseCompleter.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => receivedData,
      );

      final respString = String.fromCharCodes(respBytes.take(500));
      logger.info("Printer response received (${respBytes.length} bytes)");

      if (respString.contains("200 OK")) {
        logger.info("HTTP 200 OK: Print job successfully accepted by ipTIME CUPS server!");
      } else if (respString.isNotEmpty) {
        final firstLine = respString.split('\r\n').first;
        logger.warn("Server response status: $firstLine");
      }
    } on SocketException catch (e) {
      logger.error("Socket error connecting to $host:$port -> ${e.message}");
      rethrow;
    } on TimeoutException catch (_) {
      logger.error("Connection timed out after ${timeout.inSeconds}s");
      rethrow;
    } catch (e) {
      logger.error("Print transmission error: $e");
      rethrow;
    } finally {
      try {
        await socket?.close();
        socket?.destroy();
      } catch (_) {}
    }
  }
}
