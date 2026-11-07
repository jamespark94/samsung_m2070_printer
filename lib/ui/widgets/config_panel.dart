import 'package:flutter/material.dart';
import '../../models/print_config.dart';

class ConfigPanel extends StatelessWidget {
  final PrintConfig config;
  final ValueChanged<PrintConfig> onChanged;
  final bool isPrinting;

  const ConfigPanel({
    super.key,
    required this.config,
    required this.onChanged,
    required this.isPrinting,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.print, color: Colors.indigo),
                const SizedBox(width: 8),
                Text("프린터 연결 및 인쇄 옵션", style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
            const Divider(height: 20),

            // Protocol Selection (IPP vs RAW TCP)
            Row(
              children: [
                const Text("전송 프로토콜: "),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("IPP/HTTP (631, ipTIME 기본)"),
                  selected: config.protocol == ConnectionProtocol.ipp,
                  onSelected: isPrinting ? null : (_) {
                    onChanged(config.copyWith(
                      protocol: ConnectionProtocol.ipp,
                      port: 631,
                    ));
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("RAW TCP (9100)"),
                  selected: config.protocol == ConnectionProtocol.rawTcp,
                  onSelected: isPrinting ? null : (_) {
                    onChanged(config.copyWith(
                      protocol: ConnectionProtocol.rawTcp,
                      port: 9100,
                    ));
                  },
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Target IP & Port
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    initialValue: config.ip,
                    enabled: !isPrinting,
                    decoration: const InputDecoration(
                      labelText: "공유기 IP (ipTIME)",
                      hintText: "192.168.0.1",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) => onChanged(config.copyWith(ip: val.trim())),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey("port_${config.port}"),
                    initialValue: config.port.toString(),
                    enabled: !isPrinting,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: "포트",
                      hintText: "631",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final p = int.tryParse(val.trim());
                      if (p != null) onChanged(config.copyWith(port: p));
                    },
                  ),
                ),
              ],
            ),

            // Printer URI Path for IPP
            if (config.protocol == ConnectionProtocol.ipp) ...[
              const SizedBox(height: 12),
              TextFormField(
                initialValue: config.printerPath,
                enabled: !isPrinting,
                decoration: const InputDecoration(
                  labelText: "IPP 프린터 경로",
                  hintText: "/printers/ipTIME_Printer",
                  helperText: "최종 주소: http://192.168.0.1:631/printers/ipTIME_Printer",
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (val) => onChanged(config.copyWith(printerPath: val.trim())),
              ),
            ],

            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      const Text("인쇄 매수: "),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        onPressed: (!isPrinting && config.copies > 1)
                            ? () => onChanged(config.copyWith(copies: config.copies - 1))
                            : null,
                      ),
                      Text("${config.copies}매", style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        onPressed: (!isPrinting && config.copies < 99)
                            ? () => onChanged(config.copyWith(copies: config.copies + 1))
                            : null,
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: config.resolutionDpi,
                    decoration: const InputDecoration(
                      labelText: "해상도",
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 600, child: Text("600 DPI (고품질)")),
                      DropdownMenuItem(value: 300, child: Text("300 DPI (고속)")),
                    ],
                    onChanged: isPrinting ? null : (val) {
                      if (val != null) onChanged(config.copyWith(resolutionDpi: val));
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const Text("모노 변환 방식: "),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("사진/그림 (디더링)"),
                  selected: config.halftoneMode == HalftoneMode.dithering,
                  onSelected: isPrinting ? null : (_) {
                    onChanged(config.copyWith(halftoneMode: HalftoneMode.dithering));
                  },
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text("텍스트 (선명하게)"),
                  selected: config.halftoneMode == HalftoneMode.threshold,
                  onSelected: isPrinting ? null : (_) {
                    onChanged(config.copyWith(halftoneMode: HalftoneMode.threshold));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
