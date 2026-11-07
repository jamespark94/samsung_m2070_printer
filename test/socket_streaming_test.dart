import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_m2070_printer/services/raw_socket_client.dart';

void main() {
  group('RAW TCP Socket Client Streaming Tests', () {
    test('Streams 32KB chunks sequentially to TCP server', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverPort = server.port;

      final receivedBytes = <int>[];
      final serverCompleter = Completer<void>();

      server.listen((Socket clientSocket) {
        clientSocket.listen(
          (data) {
            receivedBytes.addAll(data);
          },
          onDone: () {
            clientSocket.close();
            serverCompleter.complete();
          },
        );
      });

      // Prepare 100 KB test payload (spread into two packets)
      final packet1 = Uint8List(60 * 1024);
      final packet2 = Uint8List(40 * 1024);
      for (int i = 0; i < packet1.length; i++) {
        packet1[i] = i % 256;
      }
      for (int i = 0; i < packet2.length; i++) {
        packet2[i] = (i + 10) % 256;
      }

      final client = RawSocketClient();
      int lastSent = 0;
      int lastTotal = 0;

      await client.sendPayload(
        host: '127.0.0.1',
        port: serverPort,
        bytePackets: [packet1, packet2],
        onProgress: (sent, total) {
          lastSent = sent;
          lastTotal = total;
        },
      );

      await serverCompleter.future;
      await server.close();

      expect(lastTotal, equals(100 * 1024));
      expect(lastSent, equals(100 * 1024));
      expect(receivedBytes.length, equals(100 * 1024));
      expect(receivedBytes.sublist(0, 100), equals(packet1.sublist(0, 100)));
    });
  });
}
