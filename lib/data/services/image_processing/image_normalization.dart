import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:image/image.dart' as img;

class NormalizedImageResult {
  final File file;
  final int? width;
  final int? height;
  final bool normalized;

  const NormalizedImageResult({
    required this.file,
    this.width,
    this.height,
    this.normalized = false,
  });
}

Future<NormalizedImageResult> normalizeReceiptImage(File file) async {
  final lowerPath = file.path.toLowerCase();
  if (lowerPath.endsWith('.pdf')) {
    return NormalizedImageResult(file: file);
  }

  try {
    final bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      _recordNormalizationFailure(
        Exception('Image bytes were empty.'),
        StackTrace.current,
      );
      return NormalizedImageResult(file: file);
    }

    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      _recordNormalizationFailure(
        Exception('Failed to decode image bytes.'),
        StackTrace.current,
      );
      return NormalizedImageResult(file: file);
    }

    var oriented = img.bakeOrientation(decoded);

    const int minWidth = 1400;
    if (oriented.width < minWidth) {
      final scaledHeight =
          (oriented.height * (minWidth / oriented.width)).round();
      oriented = img.copyResize(
        oriented,
        width: minWidth,
        height: scaledHeight,
        interpolation: img.Interpolation.average,
      );
    }

    final quality = Platform.isAndroid ? 85 : 90;
    final jpgBytes = img.encodeJpg(oriented, quality: quality);

    final normalizedFile = File(_normalizedFilePath(file.path));
    await normalizedFile.writeAsBytes(
      Uint8List.fromList(jpgBytes),
      flush: true,
    );

    return NormalizedImageResult(
      file: normalizedFile,
      width: oriented.width,
      height: oriented.height,
      normalized: true,
    );
  } catch (e, s) {
    _recordNormalizationFailure(e, s);
    return NormalizedImageResult(file: file);
  }
}

void _recordNormalizationFailure(Object error, StackTrace stackTrace) {
  FirebaseCrashlytics.instance.recordError(
    error,
    stackTrace,
    fatal: false,
    reason: 'IMAGE_NORMALIZATION_FAILED',
  );
}

String _normalizedFilePath(String originalPath) {
  final extensionMatch = RegExp(r'\.[^./\\]+$').firstMatch(originalPath);
  if (extensionMatch == null) {
    return '${originalPath}_normalized.jpg';
  }
  return originalPath.replaceFirst(
    extensionMatch.group(0)!,
    '_normalized.jpg',
  );
}
