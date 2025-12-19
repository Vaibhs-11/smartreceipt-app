import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

/// Error codes exposed by [ReceiptImageSourceService].
enum ReceiptImageSourceError { permissionDenied, unavailable, unknown }

enum CameraFallbackSelection { gallery, files }

class ReceiptImageSourceFailure {
  final ReceiptImageSourceError code;
  final String message;

  const ReceiptImageSourceFailure({
    required this.code,
    required this.message,
  });
}

class ReceiptImagePickResult {
  final File? file;
  final ReceiptImageSourceFailure? failure;

  const ReceiptImagePickResult._({this.file, this.failure});

  bool get hasFile => file != null;
  bool get wasCancelled => file == null && failure == null;
  bool get hasError => failure != null;

  factory ReceiptImagePickResult.success(File file) =>
      ReceiptImagePickResult._(file: file);

  factory ReceiptImagePickResult.cancelled() =>
      const ReceiptImagePickResult._();

  factory ReceiptImagePickResult.error(ReceiptImageSourceFailure failure) =>
      ReceiptImagePickResult._(failure: failure);
}

/// Wraps [ImagePicker] usage so UI widgets don't deal with platform errors.
class ReceiptImageSourceService {
  ReceiptImageSourceService({ImagePicker? picker})
      : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<ReceiptImagePickResult> pickFromCamera() async {
    try {
      return await _pick(ImageSource.camera);
    } on PlatformException catch (e, stackTrace) {
      debugPrint('Camera capture failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return ReceiptImagePickResult.error(_mapPlatformException(e));
    } catch (e, stackTrace) {
      debugPrint('Unknown camera capture failure: $e');
      debugPrintStack(stackTrace: stackTrace);
      return _unknownFailureResult;
    }
  }

  Future<ReceiptImagePickResult> pickFromGallery() async {
    try {
      return await _pick(ImageSource.gallery);
    } on PlatformException catch (e, stackTrace) {
      debugPrint('Gallery pick failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      return ReceiptImagePickResult.error(_mapPlatformException(e));
    } catch (e, stackTrace) {
      debugPrint('Unknown gallery pick failure: $e');
      debugPrintStack(stackTrace: stackTrace);
      return _unknownFailureResult;
    }
  }

  Future<ReceiptImagePickResult> _pick(ImageSource source) async {
    final XFile? file = await _picker.pickImage(
      source: source,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (file == null) {
      return ReceiptImagePickResult.cancelled();
    }
    return ReceiptImagePickResult.success(File(file.path));
  }

  ReceiptImageSourceFailure _mapPlatformException(PlatformException e) {
    switch (e.code) {
      case 'camera_access_denied':
      case 'camera_access_denied_permanently':
      case 'camera_access_restricted':
      case 'photo_access_denied':
      case 'photo_access_denied_permanently':
      case 'photo_access_restricted':
      case 'permission_denied':
        return const ReceiptImageSourceFailure(
          code: ReceiptImageSourceError.permissionDenied,
          message:
              'Camera access is denied. Please enable permissions in Settings.',
        );
      case 'camera_unavailable':
        return const ReceiptImageSourceFailure(
          code: ReceiptImageSourceError.unavailable,
          message: 'Camera is unavailable on this device.',
        );
      default:
        return const ReceiptImageSourceFailure(
          code: ReceiptImageSourceError.unknown,
          message: 'Unable to pick an image. Please try again.',
        );
    }
  }

  static const ReceiptImageSourceFailure _unknownFailure =
      ReceiptImageSourceFailure(
    code: ReceiptImageSourceError.unknown,
    message: 'Unable to access your images right now. Please try again.',
  );

  ReceiptImagePickResult get _unknownFailureResult =>
      ReceiptImagePickResult.error(_unknownFailure);

  Future<CameraFallbackSelection?> showCameraFallbackDialog(
    BuildContext context,
  ) {
    return showDialog<CameraFallbackSelection>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Camera not available'),
          content: const Text(
            'Camera is not available on this device. Would you like to upload a receipt from your gallery or files instead?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(CameraFallbackSelection.files),
              child: const Text('Upload from Files'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext)
                  .pop(CameraFallbackSelection.gallery),
              child: const Text('Upload from Gallery'),
            ),
          ],
        );
      },
    );
  }
}
