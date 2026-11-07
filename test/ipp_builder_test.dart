import 'package:flutter_test/flutter_test.dart';
import 'package:samsung_m2070_printer/services/ipp_packet_builder.dart';

void main() {
  group('IPP Packet Builder Tests', () {
    test('Constructs valid IPP 1.1 Print-Job header with attributes', () {
      final header = IppPacketBuilder.createPrintJobHeader(
        printerUri: "http://192.168.0.1:631/printers/ipTIME_Printer",
        jobName: "TestDoc.pdf",
        documentFormat: "application/octet-stream",
        copies: 2,
      );

      expect(header.length, greaterThan(20));
      // IPP version 1.1
      expect(header[0], equals(0x01));
      expect(header[1], equals(0x01));

      // Operation: Print-Job (0x0002)
      expect(header[2], equals(0x00));
      expect(header[3], equals(0x02));

      // Last byte should be end-of-attributes-tag (0x03)
      expect(header.last, equals(0x03));
    });
  });
}
