import 'package:cloud_functions/cloud_functions.dart';

/// Simple helper that triggers a backend job to enhance receipt images.
/// The backend should read [receiptId], fetch the original image, create an
/// enhanced version, and update Firestore with the processed path + status.
class ReceiptImageProcessingService {
  ReceiptImageProcessingService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseFunctions _functions;

  Future<void> enqueueEnhancement({
    required String receiptId,
    required String originalImagePath,
  }) async {
    /*
    if (originalImagePath.isEmpty) return;

    try {
      final callable = _functions.httpsCallable('enhanceReceiptImage');
      await callable.call({
        'receiptId': receiptId,
        'originalImagePath': originalImagePath,
      });
    } catch (e, stack) {
      debugPrint(
          'Failed to trigger receipt image enhancement for $receiptId: $e\n$stack');
    }
  */
  }
}
