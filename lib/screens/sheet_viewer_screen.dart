import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:pdfx/pdfx.dart';
import '../theme/app_theme.dart';

/// 악보(이미지 또는 PDF)를 전체화면으로 확대·축소하여 볼 수 있는 뷰어.
/// 완전 오프라인 - 로컬 바이트 데이터를 직접 렌더링한다.
class SheetViewerScreen extends StatefulWidget {
  final Uint8List bytes;
  final String mime;
  final String title;

  const SheetViewerScreen({
    super.key,
    required this.bytes,
    required this.mime,
    required this.title,
  });

  @override
  State<SheetViewerScreen> createState() => _SheetViewerScreenState();
}

class _SheetViewerScreenState extends State<SheetViewerScreen> {
  PdfControllerPinch? _pdfController;
  bool get _isPdf => widget.mime == 'application/pdf';

  @override
  void initState() {
    super.initState();
    if (_isPdf) {
      _pdfController = PdfControllerPinch(
        document: PdfDocument.openData(widget.bytes),
      );
    }
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: AppColors.ink,
        title: Text(
          widget.title,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isPdf
          ? PdfViewPinch(controller: _pdfController!)
          : InteractiveViewer(
              minScale: 0.5,
              maxScale: 5,
              child: Center(
                child: Image.memory(widget.bytes, fit: BoxFit.contain),
              ),
            ),
    );
  }
}
