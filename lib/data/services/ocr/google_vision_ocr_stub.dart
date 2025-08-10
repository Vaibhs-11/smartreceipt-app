import 'dart:math';

import 'package:smartreceipt/data/services/ocr/ocr_service.dart';

class GoogleVisionOcrStub implements OcrService {
  @override
  Future<OcrResult> parseImage(String imagePath) async {
    // Deterministic-but-fake parse for demo
    final int seed = imagePath.hashCode;
    final Random rng = Random(seed);
    final List<String> stores = <String>['Target', 'Best Buy', 'Tesco', 'Coles', 'Reliance'];
    final String storeName = stores[rng.nextInt(stores.length)];
    final DateTime date = DateTime.now().subtract(Duration(days: rng.nextInt(30)));
    final double total = (rng.nextDouble() * 200).clamp(5.0, 200.0);
    return OcrResult(storeName: storeName, date: date, total: double.parse(total.toStringAsFixed(2)));
  }
}


