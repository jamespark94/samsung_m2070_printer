import 'dart:async';
import 'dart:io';
import 'print_logger.dart';

class RawSocketClient {
  static const int chunkSize = 32 * 1024; // 32 KB chunking to prevent printer spool buffer overflows

  Future<void> sendPayload({
    required String host,
    required int port,
    required List<List<int>> bytePackets,
    required void Function(int sentBytes, int totalBytes) onProgress,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final logger = PrintLogger.instance;
    final totalBytes = bytePackets.fold<int>(0, (sum, packet) => sum + packet.length);
    logger.info("Connecting to $host:$port (Timeout: ${timeout.inSeconds}s)...");

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);
      logger.info("Connected successfully to $host:$port. Streaming $totalBytes bytes...");

      int sentBytes = 0;

      for (final packet in bytePackets) {
        int offset = 0;
        while (offset < packet.length) {
          final end = (offset + chunkSize < packet.length) ? offset + chunkSize : packet.length;
          final chunk = (offset == 0 && end == packet.length) 
              ? packet 
              : packet.sublist(offset, end);
          
          socket.add(chunk);
          sentBytes += chunk.length;
          offset = end;

          onProgress(sentBytes, totalBytes);
          // Yield to event loop to allow flush and UI updates
          await socket.flush();
        }
      }

      logger.info("Flushing socket output...");
      await socket.flush();
      logger.info("Payload completely sent ($sentBytes/$totalBytes bytes). Closing socket gracefully.");
    } on SocketException catch (e) {
      logger.error("Socket error: ${e.message} (osError: ${e.osError})");
      rethrow;
    } on TimeoutException catch (_) {
      logger.error("Connection timed out after ${timeout.inSeconds}s connecting to $host:$port");
      rethrow;
    } catch (e) {
      logger.error("Unexpected network error: $e");
      rethrow;
    } finally {
      try {
        await socket?.close();
        socket?.destroy();
      } catch (_) {}
    }
  }
}
