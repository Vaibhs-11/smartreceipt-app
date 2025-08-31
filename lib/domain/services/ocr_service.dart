import '../entities/ocr_result.dart';

abstract class OcrService {
  /// Parses an image from a Google Cloud Storage path.
  Future<OcrResult> parseImage(String gcsPath);

  /// Parses a PDF from a Google Cloud Storage path.
  Future<OcrResult> parsePdf(String gcsPath);
}
