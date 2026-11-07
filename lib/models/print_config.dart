enum HalftoneMode {
  threshold,
  dithering,
}

enum DarkThemeInvertMode {
  auto,   // 어두운 배경 자동 감지 후 반전 (기본값)
  always, // 항상 반전
  off,    // 원본 유지
}

enum ConnectionProtocol {
  ipp, // http://192.168.0.1:631/printers/ipTIME_Printer (CUPS/IPP - Default for ipTIME)
  rawTcp, // RAW TCP 9100
}

class PrintConfig {
  final String ip;
  final int port;
  final String printerPath;
  final ConnectionProtocol protocol;
  final int copies;
  final int resolutionDpi;
  final HalftoneMode halftoneMode;
  final DarkThemeInvertMode darkThemeInvertMode;
  final String paperSize;

  const PrintConfig({
    this.ip = '192.168.0.1',
    this.port = 631,
    this.printerPath = '/printers/ipTIME_Printer',
    this.protocol = ConnectionProtocol.ipp,
    this.copies = 1,
    this.resolutionDpi = 600,
    this.halftoneMode = HalftoneMode.dithering,
    this.darkThemeInvertMode = DarkThemeInvertMode.auto,
    this.paperSize = 'A4',
  });

  String get fullUri {
    if (protocol == ConnectionProtocol.ipp) {
      return "http://$ip:$port$printerPath";
    } else {
      return "$ip:$port";
    }
  }

  PrintConfig copyWith({
    String? ip,
    int? port,
    String? printerPath,
    ConnectionProtocol? protocol,
    int? copies,
    int? resolutionDpi,
    HalftoneMode? halftoneMode,
    DarkThemeInvertMode? darkThemeInvertMode,
    String? paperSize,
  }) {
    return PrintConfig(
      ip: ip ?? this.ip,
      port: port ?? this.port,
      printerPath: printerPath ?? this.printerPath,
      protocol: protocol ?? this.protocol,
      copies: copies ?? this.copies,
      resolutionDpi: resolutionDpi ?? this.resolutionDpi,
      halftoneMode: halftoneMode ?? this.halftoneMode,
      darkThemeInvertMode: darkThemeInvertMode ?? this.darkThemeInvertMode,
      paperSize: paperSize ?? this.paperSize,
    );
  }
}
