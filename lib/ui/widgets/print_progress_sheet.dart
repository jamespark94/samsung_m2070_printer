import 'package:flutter/material.dart';
import '../../models/print_job_state.dart';

class PrintProgressSheet extends StatelessWidget {
  final PrintJobProgress progress;

  const PrintProgressSheet({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    if (progress.step == PrintStep.idle) return const SizedBox.shrink();

    String stepTitle = "";
    double? linearValue;

    switch (progress.step) {
      case PrintStep.rendering:
        stepTitle = "1. 고해상도 PDF 렌더링 중 (${progress.currentPage + 1}/${progress.totalPages}페이지)...";
        linearValue = progress.totalPages > 0 ? (progress.currentPage / progress.totalPages) : null;
        break;
      case PrintStep.encoding:
        stepTitle = "2. SPLv2 / JBIG1 인코딩 중 (${progress.currentPage + 1}/${progress.totalPages}페이지)...";
        linearValue = progress.totalPages > 0 ? ((progress.currentPage + 0.5) / progress.totalPages) : null;
        break;
      case PrintStep.sending:
        stepTitle = "3. RAW 소켓 전송 중 (${(progress.sentBytes / 1024).toStringAsFixed(1)} KB / ${(progress.totalBytes / 1024).toStringAsFixed(1)} KB)...";
        linearValue = progress.totalBytes > 0 ? (progress.sentBytes / progress.totalBytes) : null;
        break;
      case PrintStep.completed:
        stepTitle = "인쇄 전송 완료!";
        linearValue = 1.0;
        break;
      case PrintStep.error:
        stepTitle = "인쇄 오류 발생";
        linearValue = 1.0;
        break;
      case PrintStep.idle:
        break;
    }

    final isError = progress.step == PrintStep.error;
    final isDone = progress.step == PrintStep.completed;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : (isDone ? Colors.green.shade50 : Colors.blue.shade50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError ? Colors.red.shade300 : (isDone ? Colors.green.shade300 : Colors.blue.shade300),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (!isError && !isDone)
                const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              else if (isDone)
                const Icon(Icons.check_circle, color: Colors.green)
              else
                const Icon(Icons.error, color: Colors.red),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  stepTitle,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isError ? Colors.red.shade800 : (isDone ? Colors.green.shade800 : Colors.blue.shade900),
                  ),
                ),
              ),
            ],
          ),
          if (progress.statusMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(progress.statusMessage, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
          ],
          if (linearValue != null && !isError && !isDone) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: linearValue),
          ],
        ],
      ),
    );
  }
}
