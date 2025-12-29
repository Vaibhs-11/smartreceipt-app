import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smartreceipt/core/constants/app_constants.dart';
import 'package:smartreceipt/domain/entities/app_user.dart';
import 'package:smartreceipt/domain/entities/receipt.dart'
    show Receipt, ReceiptItem;
import 'package:smartreceipt/domain/policies/account_policies.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:uuid/uuid.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart' show OcrResult;
import 'package:smartreceipt/domain/services/ocr_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:smartreceipt/services/receipt_image_source_service.dart';
import 'package:smartreceipt/presentation/screens/trial_ended_gate_screen.dart';
import 'package:smartreceipt/presentation/screens/purchase_screen.dart';

class UploadedFile {
  final String downloadUrl;
  final String gcsUri;
  UploadedFile({required this.downloadUrl, required this.gcsUri});
}

enum AddReceiptInitialAction { pickGallery, pickFiles }

enum _NonReceiptAction { camera, gallery, files, none }

class AddReceiptScreenArgs {
  final String? initialImagePath;
  final AddReceiptInitialAction? initialAction;

  const AddReceiptScreenArgs({this.initialImagePath, this.initialAction});
}

class AddReceiptScreen extends ConsumerStatefulWidget {
  final String? initialImagePath;
  final AddReceiptInitialAction? initialAction;

  const AddReceiptScreen({super.key, this.initialImagePath, this.initialAction});

  @override
  ConsumerState<AddReceiptScreen> createState() => _AddReceiptScreenState();
}

class _AddReceiptScreenState extends ConsumerState<AddReceiptScreen> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // Basic controllers
  final TextEditingController _storeCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();

  // New-item controllers (kept only for the "add row")
  final TextEditingController _itemNameCtrl = TextEditingController();
  final TextEditingController _itemPriceCtrl = TextEditingController();

  final String receiptId = const Uuid().v4();
  List<ReceiptItem> _items = [];

  final List<String> _currencyOptions =
      List<String>.from(AppConstants.supportedCurrencies);
  String _currency = AppConstants.supportedCurrencies.first;
  DateTime _date = DateTime.now();
  String? _originalImagePath;
  String? _processedImagePath;
  String? _imageProcessingStatus;
  String? _extractedText;
  bool _isLoading = false;
  bool _receiptRejected = false;
  // Tracks "not a receipt" reason; currently unused in UI but kept for future UX.
  // ignore: unused_field
  String? _receiptRejectionReason;
  List<String> _searchKeywords = const [];
  String? _normalizedBrand;
  String? _category;
  bool _initialArgsHandled = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat.yMMMd().format(_date);
    _handleInitialArgs();
  }

  @override
  void didUpdateWidget(covariant AddReceiptScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialImagePath != oldWidget.initialImagePath ||
        widget.initialAction != oldWidget.initialAction) {
      _initialArgsHandled = false;
      _handleInitialArgs();
    }
  }

  @override
  void dispose() {
    _storeCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    _dateCtrl.dispose();
    _itemNameCtrl.dispose();
    _itemPriceCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// Helper to build a card for a single item. Uses initialValue + ValueKey
  /// so it rebuilds correctly when OCR results replace the items list.
  Widget _buildItemCard(int index) {
    final item = _items[index];

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            Row(
              children: [
                // Name field
                Expanded(
                  flex: 3,
                  child: TextFormField(
                    key:
                        ValueKey('item-name-$index-${item.name}-${item.price}'),
                    initialValue: item.name,
                    decoration: const InputDecoration(labelText: 'Item name'),
                    onChanged: (val) {
                      setState(() {
                        _items[index] = item.copyWith(name: val.trim());
                      });
                    },
                  ),
                ),
                const SizedBox(width: 8),
                // Price field
                Expanded(
                  flex: 2,
                  child: TextFormField(
                    key: ValueKey(
                        'item-price-$index-${item.name}-${item.price}'),
                    initialValue: item.price.toStringAsFixed(2),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(labelText: 'Price'),
                    onChanged: (val) {
                      final p = double.tryParse(val.trim());
                      if (p != null) {
                        setState(() {
                          _items[index] = item.copyWith(price: p);
                        });
                      }
                    },
                  ),
                ),
              ],
            ),
            CheckboxListTile(
              value: item.taxClaimable,
              onChanged: (val) {
                setState(() {
                  _items[index] = item.copyWith(taxClaimable: val ?? false);
                });
              },
              title: const Text('Mark as tax claimable'),
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(TextEditingController controller) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;

    final String formatted = DateFormat.yMMMd().format(picked);
    setState(() {
      controller.text = formatted;
      _date = picked;
    });
  }

  void _handleInitialArgs() {
    if (_initialArgsHandled) return;

    final path = widget.initialImagePath;
    if (path != null && path.isNotEmpty) {
      final file = File(path);
      if (!file.existsSync()) {
        debugPrint('Initial image path does not exist: $path');
      } else {
        _initialArgsHandled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _processAndUploadFile(file);
        });
        return;
      }
    }

    final action = widget.initialAction;
    if (action != null) {
      _initialArgsHandled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        switch (action) {
          case AddReceiptInitialAction.pickGallery:
            _handleGalleryPick();
            break;
          case AddReceiptInitialAction.pickFiles:
            _pickFile();
            break;
        }
      });
    }
  }

  Future<bool> _ensureCanAddReceipt() async {
    final userRepo = ref.read(userRepositoryProvider);
    final receiptRepo = ref.read(receiptRepositoryProviderOverride);
    final now = DateTime.now().toUtc();
    final profile = await userRepo.getCurrentUserProfile();
    final receiptCount = await receiptRepo.getReceiptCount();

    final allowed =
        AccountPolicies.canAddReceipt(profile, receiptCount, now);
    if (allowed) return true;

    if (AccountPolicies.isExpired(profile, now) && receiptCount <= 3) {
      await userRepo.clearDowngradeRequired();
      final refreshed = await userRepo.getCurrentUserProfile();
      if (AccountPolicies.canAddReceipt(refreshed, receiptCount, now)) {
        return true;
      }
    }

    final needsGate = AccountPolicies.downgradeRequired(
      profile,
      receiptCount,
      now,
    );

    if (needsGate && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) => TrialEndedGateScreen(
            isSubscriptionEnded: profile.accountStatus == AccountStatus.paid,
            receiptCount: receiptCount,
          ),
        ),
        (_) => false,
      );
      return false;
    }

    if (mounted) {
      await _showLimitDialog(profile, receiptCount);
    }
    return false;
  }

  Future<void> _showLimitDialog(
    AppUserProfile profile,
    int receiptCount,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Free plan limit reached'),
        content: Text(
          'You have $receiptCount receipts. Start a free 7-day trial '
          'or upgrade to keep adding more.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _startTrial();
            },
            child: const Text('Start trial'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PurchaseScreen()),
              );
            },
            child: const Text('Upgrade'),
          ),
        ],
      ),
    );
  }

  Future<void> _startTrial() async {
    final userRepo = ref.read(userRepositoryProvider);
    await userRepo.startTrial();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Trial started. You can now add receipts.')),
    );
  }

  Future<void> _submit() async {
    final addReceipt = ref.read(addReceiptUseCaseProviderOverride);
    final imageProcessor = ref.read(receiptImageProcessingServiceProvider);
    final navigator = Navigator.of(context);

    final ok = await _ensureCanAddReceipt();
    if (!ok) return;
    if (_receiptRejected) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final double total = double.tryParse(_totalCtrl.text.trim()) ?? 0;

    final receipt = Receipt(
      id: receiptId,
      storeName: _storeCtrl.text.trim(),
      date: _date,
      total: total,
      currency: _currency,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      imagePath: _originalImagePath,
      originalImagePath: _originalImagePath,
      processedImagePath: _processedImagePath,
      imageProcessingStatus: _imageProcessingStatus,
      extractedText: _extractedText,
      items: _items,
      searchKeywords: _searchKeywords,
      normalizedBrand: _normalizedBrand,
      category: _category,
    );

    await addReceipt(receipt);
    if (_originalImagePath != null && _originalImagePath!.isNotEmpty) {
      unawaited(imageProcessor.enqueueEnhancement(
        receiptId: receiptId,
        originalImagePath: _originalImagePath!,
      ));
    }

    if (mounted) {
      navigator.pop();
    }
  }

  Future<UploadedFile?> _uploadFileToStorage(File file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Cannot upload file, user not logged in.");
      return null;
    }
    try {
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("receipts")
          .child(user.uid)
          .child(receiptId)
          .child(file.path.split('/').last);

      await storageRef.putFile(file);
      final downloadUrl = await storageRef.getDownloadURL();
      final gcsUri = 'gs://${storageRef.bucket}/${storageRef.fullPath}';
      return UploadedFile(downloadUrl: downloadUrl, gcsUri: gcsUri);
    } catch (e) {
      debugPrint("Upload failed: $e");
      return null;
    }
  }

  void _handleOcrResult(OcrResult result, {String? uploadedUrl}) {
    if (!mounted) return;
    setState(() {
      _isLoading = false;
      _receiptRejected = false;
      _receiptRejectionReason = null;
      if (uploadedUrl != null) {
        _originalImagePath = uploadedUrl;
        _processedImagePath = null;
        _imageProcessingStatus = 'pending';
      }
      _storeCtrl.text = result.storeName;
      _totalCtrl.text = result.total.toStringAsFixed(2);
      _date = result.date;
      _dateCtrl.text = DateFormat.yMMMd().format(_date);

      if (result.items.isNotEmpty) {
        _items = result
            .toReceiptItems(); // assumes new model includes taxClaimable default
      }

      final String? parsedCurrency = result.currency?.trim().toUpperCase();
      if (parsedCurrency != null && parsedCurrency.isNotEmpty) {
        if (!_currencyOptions.contains(parsedCurrency)) {
          _currencyOptions.add(parsedCurrency);
        }
        _currency = parsedCurrency;
      }

      _searchKeywords = List<String>.from(result.searchKeywords);
      _normalizedBrand = result.normalizedBrand;
      _category = result.category;

      _extractedText = 'Store: ${result.storeName}\n'
          'Date: ${DateFormat.yMMMd().format(result.date)}\n'
          'Total: ${result.total.toStringAsFixed(2)}\n\n'
          'Raw Text:\n${result.rawText}';
    });
  }

  Future<_NonReceiptAction?> _handleNonReceipt(OcrResult result) async {
    if (!mounted) return null;
    setState(() {
      _receiptRejected = true;
      _receiptRejectionReason = result.receiptRejectionReason;
    });
    return _showNotReceiptDialog(result.receiptRejectionReason);
  }

  Future<bool> _maybeAcceptReceiptResult(
    OcrResult result, {
    String? uploadedUrl,
  }) async {
    if (!result.isReceipt) {
      final nextAction = await _handleNonReceipt(result);
      if (nextAction != null &&
          nextAction != _NonReceiptAction.none &&
          mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          switch (nextAction) {
            case _NonReceiptAction.camera:
              _handleCameraCapture();
              break;
            case _NonReceiptAction.gallery:
              _handleGalleryPick();
              break;
            case _NonReceiptAction.files:
              _pickFile();
              break;
            case _NonReceiptAction.none:
              break;
          }
        });
      }
      return false;
    }

    _handleOcrResult(result, uploadedUrl: uploadedUrl);
    return true;
  }

  Future<_NonReceiptAction?> _showNotReceiptDialog(String? reason) {
    if (!mounted) return Future.value(_NonReceiptAction.none);
    return showDialog<_NonReceiptAction>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Not a receipt'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sorry — we couldn’t confidently identify this image as a receipt, so we’re unable to store it. Please try uploading a clearer photo of a receipt.',
              ),
              if (reason != null && reason.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Details: $reason',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.none),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.files),
              child: const Text('Pick from Files'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.gallery),
              child: const Text('Pick from Gallery'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_NonReceiptAction.camera),
              child: const Text('Retry with Camera'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _processAndUploadFile(File file) async {
    final allowed = await _ensureCanAddReceipt();
    if (!allowed) return;

    setState(() {
      _isLoading = true;
      _receiptRejected = false;
      _receiptRejectionReason = null;
    });

    try {
      final String lowerPath = file.path.toLowerCase();
      final bool isPdf = lowerPath.endsWith('.pdf');
      final OcrService ocr = ref.read(ocrServiceProvider);

      if (!isPdf) {
        final uploadResult = await _uploadFileToStorage(file);
        if (uploadResult == null) throw Exception('File upload failed.');

        final gcsPath = Uri.parse(uploadResult.gcsUri).path.substring(1);
        final result = await ocr.parseImage(gcsPath);
        await _maybeAcceptReceiptResult(
          result,
          uploadedUrl: uploadResult.downloadUrl,
        );
        return;
      }

      // Try extracting selectable text from PDF
      String extractedText = '';
      try {
        final Uint8List bytes = await file.readAsBytes();
        final sfpdf.PdfDocument document = sfpdf.PdfDocument(inputBytes: bytes);
        final sfpdf.PdfTextExtractor extractor =
            sfpdf.PdfTextExtractor(document);

        final buffer = StringBuffer();
        for (int i = 0; i < document.pages.count; i++) {
          final pageText = extractor.extractText(
            startPageIndex: i,
            endPageIndex: i,
          );
          if (pageText != null && pageText.trim().isNotEmpty) {
            buffer.writeln(pageText);
          }
        }

        extractedText = buffer.toString();
        document.dispose();
      } catch (e) {
        debugPrint('PDF text extraction failed locally: $e');
      }

      if (extractedText.trim().isNotEmpty) {
        final uploadResult = await _uploadFileToStorage(file);
        if (uploadResult == null) throw Exception('File upload failed.');

        final parsed = await ocr.parseRawText(extractedText);
        await _maybeAcceptReceiptResult(
          parsed,
          uploadedUrl: uploadResult.downloadUrl,
        );
        return;
      }

      // If PDF has no selectable text → render to image
      File? tempImageFile;
      try {
        final pdfx.PdfDocument pdf = await pdfx.PdfDocument.openFile(file.path);
        final pdfx.PdfPage page = await pdf.getPage(1);

        final pdfx.PdfPageImage? pageImage = await page.render(
          width: page.width,
          height: page.height,
          format: pdfx.PdfPageImageFormat.jpeg,
          backgroundColor: '#FFFFFF',
        );

        if (pageImage == null || pageImage.bytes.isEmpty) {
          await page.close();
          await pdf.close();
          throw Exception('Failed to render PDF page to image');
        }

        final Uint8List jpgBytes = pageImage.bytes;
        await page.close();
        await pdf.close();

        final jpgPath = file.path
            .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '_p1.jpg');

        tempImageFile = File(jpgPath);
        await tempImageFile.writeAsBytes(jpgBytes, flush: true);
      } catch (e) {
        debugPrint('Failed to render PDF to image: $e');
      }

      if (tempImageFile == null || !(await tempImageFile.exists())) {
        throw Exception('Failed to convert PDF to image for OCR');
      }

      final uploadResult = await _uploadFileToStorage(tempImageFile);
      if (uploadResult == null) throw Exception('File upload failed.');

      final gcsPath = Uri.parse(uploadResult.gcsUri).path.substring(1);
      final result = await ocr.parseImage(gcsPath);
      await _maybeAcceptReceiptResult(
        result,
        uploadedUrl: uploadResult.downloadUrl,
      );
    } catch (e, s) {
      debugPrint('Error processing file: $e\n$s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error processing file: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleCameraCapture() async {
    final allowed = await _ensureCanAddReceipt();
    if (!allowed) return;
    final service = ref.read(receiptImageSourceServiceProvider);
    final result = await service.pickFromCamera();
    await _handleImageSourceResult(result, fromCamera: true);
  }

  Future<void> _handleGalleryPick() async {
    final allowed = await _ensureCanAddReceipt();
    if (!allowed) return;
    final service = ref.read(receiptImageSourceServiceProvider);
    final result = await service.pickFromGallery();
    await _handleImageSourceResult(result);
  }

  Future<void> _handleImageSourceResult(
    ReceiptImagePickResult result, {
    bool fromCamera = false,
  }) async {
    final imageService = ref.read(receiptImageSourceServiceProvider);

    if (result.file != null) {
      await _processAndUploadFile(result.file!);
      return;
    }

    final failure = result.failure;
    if (failure == null || !mounted) return;

    if (fromCamera) {
      if (failure.code == ReceiptImageSourceError.permissionDenied) {
        _showImageSourceError(failure);
        return;
      }

      final selection = await imageService.showCameraFallbackDialog(context);
      if (!mounted || selection == null) return;
      switch (selection) {
        case CameraFallbackSelection.gallery:
          await _handleGalleryPick();
          break;
        case CameraFallbackSelection.files:
          await _pickFile();
          break;
      }
      return;
    }

    _showImageSourceError(failure);
  }

  void _showImageSourceError(ReceiptImageSourceFailure failure) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(failure.message)),
    );
  }

  Future<void> _pickFile() async {
    final allowed = await _ensureCanAddReceipt();
    if (!allowed) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    await _processAndUploadFile(file);
  }

  Future<void> _showUploadOptions() async {
    final allowed = await _ensureCanAddReceipt();
    if (!allowed) return;
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Pick from Gallery'),
                onTap: () => Navigator.of(context).pop('gallery'),
              ),
              ListTile(
                leading: const Icon(Icons.insert_drive_file),
                title: const Text('Pick from Files'),
                onTap: () => Navigator.of(context).pop('files'),
              ),
            ],
          ),
        );
      },
    );

    if (!mounted) return;

    if (result == 'gallery') {
      await _handleGalleryPick();
    } else if (result == 'files') {
      await _pickFile();
    }
  }

  void _addNewItemFromInputs() {
    final name = _itemNameCtrl.text.trim();
    final price = double.tryParse(_itemPriceCtrl.text.trim());
    if (name.isNotEmpty && price != null) {
      setState(() {
        _items.add(ReceiptItem(name: name, price: price, taxClaimable: false));
        _itemNameCtrl.clear();
        _itemPriceCtrl.clear();
      });

      // After a new item is added, scroll to bottom so user can see it.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent + 150,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // bottom padding to lift Save button above keyboard when open
    final double bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final double bottomPadding = math.max(bottomInset, 12);

    return Scaffold(
      appBar: AppBar(title: const Text('Add Receipt')),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          SafeArea(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_originalImagePath != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Selected image: $_originalImagePath',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    TextFormField(
                      controller: _storeCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Store name'),
                      validator: (String? v) =>
                          v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _dateCtrl,
                      readOnly: true,
                      decoration: const InputDecoration(labelText: 'Date'),
                      onTap: () => _pickDate(_dateCtrl),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading
                                ? null
                                : () => _handleCameraCapture(),
                            icon: const Icon(Icons.photo_camera_outlined),
                            label: const Text('Capture'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isLoading ? null : _showUploadOptions,
                            icon: const Icon(Icons.upload),
                            label: const Text('Upload'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: TextFormField(
                            controller: _totalCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: const InputDecoration(
                                labelText: 'Total amount'),
                            validator: (String? v) =>
                                (double.tryParse(v ?? '') == null)
                                    ? 'Enter valid number'
                                    : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        DropdownButton<String>(
                          value: _currency,
                          onChanged: (String? v) =>
                              setState(() => _currency = v ?? _currency),
                          items: _currencyOptions
                              .map((String c) => DropdownMenuItem<String>(
                                  value: c, child: Text(c)))
                              .toList(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration:
                          const InputDecoration(labelText: 'Notes (optional)'),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 20),
                    const Text('Items',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Review items carefully. Edit names/prices if needed.\n'
                        'Tick the checkbox for tax claimable purchases.',
                        style: TextStyle(fontSize: 12, color: Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Build item cards
                    ..._items.asMap().entries.map((entry) {
                      final index = entry.key;
                      return _buildItemCard(index);
                    }).toList(),

                    const SizedBox(height: 12),
                    // Add new item row
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _itemNameCtrl,
                            decoration:
                                const InputDecoration(labelText: 'Item name'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _itemPriceCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Price'),
                          ),
                        ),
                        IconButton(
                          icon:
                              const Icon(Icons.add_circle, color: Colors.green),
                          onPressed: _addNewItemFromInputs,
                        ),
                      ],
                    ),
                    const SizedBox(
                        height: 100), // spacer so last row not hidden
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.45),
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, bottomPadding),
          child: SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isLoading || _receiptRejected ? null : _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ),
        ),
      ),
    );
  }
}
