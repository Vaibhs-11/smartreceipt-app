import 'dart:math';

import 'package:smartreceipt/domain/entities/ocr_result.dart';
import 'package:smartreceipt/domain/services/ocr_service.dart';

class GoogleVisionOcrStub implements OcrService {
  @override
  Future<OcrResult> parseImage(String gcsPath) async {
    // Deterministic-but-fake parse for demo
    final int seed = gcsPath.hashCode;
    final Random rng = Random(seed);
    final List<String> stores = <String>['Target', 'Best Buy', 'Tesco', 'Coles', 'Reliance'];
    final String storeName = stores[rng.nextInt(stores.length)];
    final DateTime date = DateTime.now().subtract(Duration(days: rng.nextInt(30)));
    final double total = (rng.nextDouble() * 200).clamp(5.0, 200.0);
    return OcrResult(
        storeName: storeName,
        date: date,
        total: double.parse(total.toStringAsFixed(2)),
        rawText: 'This is stubbed OCR text for $storeName.');
  }

  @override
  Future<OcrResult> parsePdf(String gcsPath) async {
    // For stubbing, we can reuse the same logic as parseImage.
    // A real implementation would use a PDF parsing library.
    final int seed = gcsPath.hashCode;
    final Random rng = Random(seed);
    final List<String> stores = <String>['Target', 'Best Buy', 'Tesco', 'Coles', 'Reliance'];
    final String storeName = stores[rng.nextInt(stores.length)];
    final DateTime date = DateTime.now().subtract(Duration(days: rng.nextInt(30)));
    final double total = (rng.nextDouble() * 200).clamp(5.0, 200.0);
    return OcrResult(
        storeName: storeName,
        date: date,
        total: double.parse(total.toStringAsFixed(2)),
        rawText: 'This is stubbed OCR text for PDF $storeName.');
  }
}
