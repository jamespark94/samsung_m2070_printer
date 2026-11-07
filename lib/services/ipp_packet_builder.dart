import 'dart:typed_data';

class IppPacketBuilder {
  // IPP Tags
  static const int tagOperationAttributes = 0x01;
  static const int tagJobAttributes = 0x02;
  static const int tagEndOfAttributes = 0x03;
  static const int tagPrinterAttributes = 0x04;

  // Value Tags
  static const int tagCharset = 0x47;
  static const int tagNaturalLanguage = 0x48;
  static const int tagUri = 0x45;
  static const int tagKeyword = 0x44;
  static const int tagNameWithoutLanguage = 0x42;
  static const int tagMimeMediaType = 0x49;
  static const int tagInteger = 0x21;

  // Operations
  static const int opPrintJob = 0x0002;
  static const int opGetPrinterAttributes = 0x000B;

  /// Creates a valid IPP 1.1 Print-Job binary header
  static Uint8List createPrintJobHeader({
    required String printerUri,
    String jobName = "Document.pdf",
    String documentFormat = "application/octet-stream",
    int requestId = 1,
    int copies = 1,
  }) {
    final builder = BytesBuilder();

    // 1. IPP Header (8 bytes)
    builder.addByte(0x01); // IPP Major 1
    builder.addByte(0x01); // IPP Minor 1
    builder.add([ (opPrintJob >> 8) & 0xFF, opPrintJob & 0xFF ]); // Operation: Print-Job (0x0002)
    builder.add([
      (requestId >> 24) & 0xFF,
      (requestId >> 16) & 0xFF,
      (requestId >> 8) & 0xFF,
      requestId & 0xFF,
    ]); // Request ID

    // 2. Operation Attributes Group (0x01)
    builder.addByte(tagOperationAttributes);
    _addAttribute(builder, tagCharset, 'attributes-charset', 'utf-8');
    _addAttribute(builder, tagNaturalLanguage, 'attributes-natural-language', 'en');
    _addAttribute(builder, tagUri, 'printer-uri', printerUri);
    _addAttribute(builder, tagNameWithoutLanguage, 'job-name', jobName);
    _addAttribute(builder, tagMimeMediaType, 'document-format', documentFormat);

    // 3. Job Attributes Group (0x02) - Optional copies
    if (copies > 1) {
      builder.addByte(tagJobAttributes);
      _addIntegerAttribute(builder, tagInteger, 'copies', copies);
    }

    // 4. End of attributes (0x03)
    builder.addByte(tagEndOfAttributes);

    return builder.toBytes();
  }

  static void _addAttribute(BytesBuilder builder, int tag, String name, String value) {
    builder.addByte(tag);
    final nameBytes = Uint8List.fromList(name.codeUnits);
    builder.add([ (nameBytes.length >> 8) & 0xFF, nameBytes.length & 0xFF ]);
    builder.add(nameBytes);

    final valBytes = Uint8List.fromList(value.codeUnits);
    builder.add([ (valBytes.length >> 8) & 0xFF, valBytes.length & 0xFF ]);
    builder.add(valBytes);
  }

  static void _addIntegerAttribute(BytesBuilder builder, int tag, String name, int value) {
    builder.addByte(tag);
    final nameBytes = Uint8List.fromList(name.codeUnits);
    builder.add([ (nameBytes.length >> 8) & 0xFF, nameBytes.length & 0xFF ]);
    builder.add(nameBytes);

    builder.add([ 0x00, 0x04 ]); // Integer is 4 bytes
    builder.add([
      (value >> 24) & 0xFF,
      (value >> 16) & 0xFF,
      (value >> 8) & 0xFF,
      value & 0xFF,
    ]);
  }
}
