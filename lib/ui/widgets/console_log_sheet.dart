import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/print_logger.dart';

class ConsoleLogSheet extends StatelessWidget {
  const ConsoleLogSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: PrintLogger.instance,
      builder: (context, _) {
        final logs = PrintLogger.instance.logs;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.terminal, size: 20, color: Colors.blueGrey),
                        SizedBox(width: 8),
                        Text("실행 콘솔 / 네트워크 로그", style: TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.copy, size: 18),
                          tooltip: "로그 복사",
                          onPressed: logs.isEmpty ? null : () {
                            final allText = logs.map((e) => e.toString()).join('\n');
                            Clipboard.setData(ClipboardData(text: allText));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text("로그가 클립보드에 복사되었습니다.")),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.clear_all, size: 18),
                          tooltip: "로그 지우기",
                          onPressed: logs.isEmpty ? null : () => PrintLogger.instance.clear(),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 140,
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: logs.isEmpty
                      ? const Center(
                          child: Text("기록된 로그가 없습니다.", style: TextStyle(color: Colors.grey, fontSize: 12)),
                        )
                      : ListView.builder(
                          reverse: true,
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[logs.length - 1 - index];
                            Color textColor = Colors.white70;
                            if (log.level == 'ERROR') textColor = Colors.redAccent;
                            if (log.level == 'WARN') textColor = Colors.amberAccent;

                            return Text(
                              log.toString(),
                              style: TextStyle(
                                color: textColor,
                                fontSize: 11,
                                fontFamily: 'monospace',
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
