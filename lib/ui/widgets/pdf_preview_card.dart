import 'dart:typed_data';
import 'package:flutter/material.dart';

class PdfPreviewCard extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final Uint8List? previewImageBytes;
  final bool isLoading;
  final ValueChanged<int> onPageChanged;

  const PdfPreviewCard({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.previewImageBytes,
    required this.isLoading,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "페이지 미리보기 ($totalPages 페이지 중 ${currentPage + 1})",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: (currentPage > 0 && !isLoading)
                          ? () => onPageChanged(currentPage - 1)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: (currentPage < totalPages - 1 && !isLoading)
                          ? () => onPageChanged(currentPage + 1)
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 280,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (previewImageBytes != null && previewImageBytes!.isNotEmpty)
                      ? Center(
                          child: Image.memory(
                            previewImageBytes!,
                            fit: BoxFit.contain,
                          ),
                        )
                      : const Center(child: Text("미리보기를 불러올 수 없습니다.")),
            ),
          ],
        ),
      ),
    );
  }
}
