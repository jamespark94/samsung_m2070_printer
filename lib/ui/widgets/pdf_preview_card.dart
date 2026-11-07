import 'dart:typed_data';
import 'package:flutter/material.dart';

class PdfPreviewCard extends StatefulWidget {
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
  State<PdfPreviewCard> createState() => _PdfPreviewCardState();
}

class _PdfPreviewCardState extends State<PdfPreviewCard> {
  final TransformationController _zoomController = TransformationController();

  void _resetZoom() {
    _zoomController.value = Matrix4.identity();
  }

  void _openFullScreenPreview(BuildContext context) {
    if (widget.previewImageBytes == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black87,
        child: Scaffold(
          backgroundColor: Colors.black87,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text("페이지 ${widget.currentPage + 1} / ${widget.totalPages}"),
            actions: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: widget.currentPage > 0
                    ? () {
                        Navigator.pop(ctx);
                        widget.onPageChanged(widget.currentPage - 1);
                      }
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: widget.currentPage < widget.totalPages - 1
                    ? () {
                        Navigator.pop(ctx);
                        widget.onPageChanged(widget.currentPage + 1);
                      }
                    : null,
              ),
            ],
          ),
          body: InteractiveViewer(
            minScale: 1.0,
            maxScale: 6.0,
            child: Center(
              child: Image.memory(widget.previewImageBytes!, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

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
                  "페이지 미리보기 (${widget.totalPages}장 중 ${widget.currentPage + 1}장)",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Row(
                  children: [
                    IconButton(
                      tooltip: "배율 초기화",
                      icon: const Icon(Icons.zoom_out_map, size: 20),
                      onPressed: _resetZoom,
                    ),
                    IconButton(
                      tooltip: "전체화면으로 크게 보기",
                      icon: const Icon(Icons.fullscreen),
                      onPressed: widget.previewImageBytes != null
                          ? () => _openFullScreenPreview(context)
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left),
                      onPressed: (widget.currentPage > 0 && !widget.isLoading)
                          ? () {
                              _resetZoom();
                              widget.onPageChanged(widget.currentPage - 1);
                            }
                          : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right),
                      onPressed: (widget.currentPage < widget.totalPages - 1 && !widget.isLoading)
                          ? () {
                              _resetZoom();
                              widget.onPageChanged(widget.currentPage + 1);
                            }
                          : null,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              height: 400,
              width: double.infinity,
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: widget.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (widget.previewImageBytes != null && widget.previewImageBytes!.isNotEmpty)
                      ? GestureDetector(
                          onDoubleTap: _resetZoom,
                          child: InteractiveViewer(
                            transformationController: _zoomController,
                            panEnabled: true,
                            minScale: 1.0,
                            maxScale: 5.0,
                            child: Center(
                              child: Image.memory(
                                widget.previewImageBytes!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        )
                      : const Center(child: Text("미리보기를 불러올 수 없습니다.")),
            ),
            const SizedBox(height: 6),
            const Text(
              "💡 두 손가락으로 확대/축소하거나 더블탭하여 원래 크기로 되돌릴 수 있습니다.",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
