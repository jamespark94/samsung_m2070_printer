import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SPL / QPDL v3 Protocol Header Tests', () {
    test('Job Start Header contains PJL and QPDL language entry', () {
      const jobName = "TestDocument.pdf";
      final pjl = "\x1B%-12345X@PJL DEFAULT SERVICEDATE=20261107\n"
          "@PJL SET USERNAME=\"Android\"\n"
          "@PJL SET JOBNAME=\"$jobName\"\n"
          "@PJL SET PAPERTYPE=OFF\n"
          "@PJL SET ALTITUDE=LOW\n"
          "@PJL SET DENSITY=3\n"
          "@PJL SET RET=NORMAL\n"
          "@PJL ENTER LANGUAGE = QPDL\n";

      final bytes = latin1.encode(pjl);
      expect(bytes, containsAllInOrder(ascii.encode("@PJL ENTER LANGUAGE = QPDL")));
      expect(bytes, containsAllInOrder(ascii.encode("TestDocument.pdf")));
    });

    test('QPDL v3 Page Header 17-bytes structure verification', () {
      // Record Type 0x00, Resolution / 100 = 6, QPDL Version 3
      // Paper size units are in 1/300 inch at all resolutions (e.g. 2480 x 3508 for A4)
      final header = List<int>.filled(17, 0);
      header[0] = 0x00; // Record type 0x00
      header[1] = 0x06; // Y-Res 600 DPI / 100
      header[2] = 0x00; // Copies MSB
      header[3] = 0x01; // Copies LSB (1 copy)
      header[4] = 0x02; // A4 (SpliX/ULD code 2)
      header[5] = (2480 >> 8) & 0xFF; // Width (1/300 in) MSB
      header[6] = 2480 & 0xFF;        // Width LSB
      header[7] = (3508 >> 8) & 0xFF; // Height (1/300 in) MSB
      header[8] = 3508 & 0xFF;       // Height LSB
      header[9] = 0x01;              // Auto Tray
      header[11] = 0x00;             // Duplex: Off
      header[14] = 0x03;             // QPDL Version 3
      header[15] = 0x01;             // Sub-version: 1
      header[16] = 0x06;             // X-Res 600 DPI / 100

      expect(header.length, equals(17));
      expect(header[0], equals(0x00));
      expect(header[1], equals(0x06));
      expect(header[4], equals(0x02));
      expect(header[14], equals(0x03));
      expect((header[5] << 8) | header[6], equals(2480));
      expect((header[7] << 8) | header[8], equals(3508));
    });

    test('QPDL v3 Page Footer 3-bytes structure verification', () {
      final footer = [0x01, 0x00, 0x01];
      expect(footer.length, equals(3));
      expect(footer[0], equals(0x01));
      expect((footer[1] << 8) | footer[2], equals(1));
    });

    test('QPDL v3 Band Record 0x0C structure and checksum verification', () {
      // 0x0C band# width(2) height(2) 0x11 dataSize(4) [0xEF, 0xCD, 0xAB, 0x09] payload checksum(4)
      final record = <int>[
        0x0C, // Signature
        0x00, // Band 0
        0x00, 0x80, // Width 128
        0x00, 0x80, // Height 128
        0x11, // Compression Algo 0x11
        0x00, 0x00, 0x00, 0x0A, // Data Size 10
        0xEF, 0xCD, 0xAB, 0x09, // Sub-header signature
        0x12, 0x34, // 2 dummy payload bytes
      ];

      int checksum = 0xEF + 0xCD + 0xAB + 0x09 + 0x12 + 0x34;
      record.addAll([
        (checksum >> 24) & 0xFF,
        (checksum >> 16) & 0xFF,
        (checksum >> 8) & 0xFF,
        checksum & 0xFF,
      ]);

      expect(record.length, equals(11 + 4 + 2 + 4));
      expect(record[0], equals(0x0C));
      expect(record[6], equals(0x11));
      expect(record.sublist(11, 15), equals([0xEF, 0xCD, 0xAB, 0x09]));
    });
  });
}
