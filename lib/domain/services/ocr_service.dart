import 'package:receiptnest/domain/entities/ocr_result.dart';

abstract class OcrService {
  /// Parses an image from a Google Cloud Storage path.
  Future<OcrResult> parseImage(String gcsPath);

  /// Parses a PDF from a Google Cloud Storage path.
  Future<OcrResult> parsePdf(String gcsPath);

  /// Parses directly from raw extracted text (no Vision API call).
  Future<OcrResult> parseRawText(String rawText);
}
