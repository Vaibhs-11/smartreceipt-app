import '../entities/ocr_result.dart';

abstract class OcrService {
  Future<OcrResult> parseImage(String imageUrl);

  Future<OcrResult> parsePdf(String pdfUrl);
}
