import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:smartreceipt/core/constants/app_constants.dart';
import 'package:smartreceipt/domain/entities/receipt.dart' show Receipt, ReceiptItem;
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:uuid/uuid.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart' show OcrResult;
import 'package:smartreceipt/domain/services/ocr_service.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sfpdf;
import 'package:pdfx/pdfx.dart' as pdfx;

class UploadedFile {
  final String downloadUrl;
  final String gcsUri;
  UploadedFile({required this.downloadUrl, required this.gcsUri});
}

class AddReceiptScreen extends ConsumerStatefulWidget {
  const AddReceiptScreen({super.key});

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

  String _currency = AppConstants.supportedCurrencies.first;
  DateTime _date = DateTime.now();
  String? _imagePath;
  String? _extractedText;
  bool _isLoading = false;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _dateCtrl.text = DateFormat.yMMMd().format(_date);
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
                    key: ValueKey('item-name-$index-${item.name}-${item.price}'),
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
                    key: ValueKey('item-price-$index-${item.name}-${item.price}'),
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

  Future<void> _submit() async {
  if (!(_formKey.currentState?.validate() ?? false)) return;

  final navigator = Navigator.of(context);
  final double total = double.tryParse(_totalCtrl.text.trim()) ?? 0;

  final receipt = Receipt(
    id: receiptId,
    storeName: _storeCtrl.text.trim(),
    date: _date,
    total: total,
    currency: _currency,
    notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
    imagePath: _imagePath,
    extractedText: _extractedText,
    items: _items,
  );

  // Correct provider
  final addReceipt = ref.read(addReceiptUseCaseProviderOverride);

  await addReceipt(receipt);

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
      if (uploadedUrl != null) {
        _imagePath = uploadedUrl;
      }
      _storeCtrl.text = result.storeName;
      _totalCtrl.text = result.total.toStringAsFixed(2);
      _date = result.date;
      _dateCtrl.text = DateFormat.yMMMd().format(_date);

      if (result.items.isNotEmpty) {
        _items = result.toReceiptItems(); // assumes new model includes taxClaimable default
      }

      _extractedText =
          'Store: ${result.storeName}\n'
          'Date: ${DateFormat.yMMMd().format(result.date)}\n'
          'Total: ${result.total.toStringAsFixed(2)}\n\n'
          'Raw Text:\n${result.rawText}';
    });
  }

  Future<void> _processAndUploadFile(File file) async {
    setState(() => _isLoading = true);

    try {
      final String lowerPath = file.path.toLowerCase();
      final bool isPdf = lowerPath.endsWith('.pdf');
      final OcrService ocr = ref.read(ocrServiceProvider);

      if (!isPdf) {
        final uploadResult = await _uploadFileToStorage(file);
        if (uploadResult == null) throw Exception('File upload failed.');

        final gcsPath = Uri.parse(uploadResult.gcsUri).path.substring(1);
        final result = await ocr.parseImage(gcsPath);
        _handleOcrResult(result, uploadedUrl: uploadResult.downloadUrl);
        return;
      }

      // Try extracting selectable text from PDF
      String extractedText = '';
      try {
        final Uint8List bytes = await file.readAsBytes();
        final sfpdf.PdfDocument document =
            sfpdf.PdfDocument(inputBytes: bytes);
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
        _handleOcrResult(parsed, uploadedUrl: uploadResult.downloadUrl);
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

        final jpgPath =
            file.path.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '_p1.jpg');

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
      _handleOcrResult(result, uploadedUrl: uploadResult.downloadUrl);
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

  Future<void> _pickImage({required bool fromCamera}) async {
    final picker = ImagePicker();
    final XFile? file = await (fromCamera
        ? picker.pickImage(source: ImageSource.camera)
        : picker.pickImage(source: ImageSource.gallery));
    if (file == null) return;

    await _processAndUploadFile(File(file.path));
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);
    await _processAndUploadFile(file);
  }

  Future<void> _showUploadOptions() async {
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
      await _pickImage(fromCamera: false);
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
                  if (_imagePath != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        'Selected image: $_imagePath',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  TextFormField(
                    controller: _storeCtrl,
                    decoration: const InputDecoration(labelText: 'Store name'),
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
                          onPressed:
                              _isLoading ? null : () => _pickImage(fromCamera: true),
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
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          decoration:
                              const InputDecoration(labelText: 'Total amount'),
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
                        items: AppConstants.supportedCurrencies
                            .map((String c) =>
                                DropdownMenuItem<String>(value: c, child: Text(c)))
                            .toList(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notesCtrl,
                    decoration: const InputDecoration(labelText: 'Notes (optional)'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 20),
                  const Text('Items',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
                          decoration: const InputDecoration(labelText: 'Item name'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _itemPriceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(labelText: 'Price'),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle, color: Colors.green),
                        onPressed: _addNewItemFromInputs,
                      ),
                    ],
                  ),
                  const SizedBox(height: 100), // spacer so last row not hidden
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
            onPressed: _isLoading ? null : _submit,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
        ),
      ),
    ),
  );
}
}
