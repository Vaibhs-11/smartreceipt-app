class OcrResult {
  OcrResult({this.storeName, this.date, this.total});
  final String? storeName;
  final DateTime? date;
  final double? total;
}

abstract class OcrService {
  Future<OcrResult> parseImage(String imagePath);
}


