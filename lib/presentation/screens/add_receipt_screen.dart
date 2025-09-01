import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:pdfx/pdfx.dart';
import 'package:path/path.dart' as path;
import 'package:pdf_text/pdf_text.dart';
import 'package:smartreceipt/domain/services/receipt_parser.dart';
import 'package:smartreceipt/core/constants/app_constants.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:uuid/uuid.dart';
import 'package:smartreceipt/domain/entities/ocr_result.dart';

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
  final TextEditingController _storeCtrl = TextEditingController();
  final TextEditingController _totalCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();
  final TextEditingController _dateCtrl = TextEditingController();
  final TextEditingController _expiryCtrl = TextEditingController();
  final String receiptId = const Uuid().v4();
  String _currency = AppConstants.supportedCurrencies.first;
  DateTime _date = DateTime.now();
  DateTime? _expiry;
  String? _imagePath;
  String? _extractedText;
  bool _isLoading = false;

  @override
  void dispose() {
    _storeCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    _dateCtrl.dispose();
    _expiryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate(TextEditingController controller, {bool isExpiry = false}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isExpiry ? (_expiry ?? DateTime.now()) : _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || picked == null) return;

    final String formatted = DateFormat.yMMMd().format(picked);
    setState(() {
      controller.text = formatted;
      if (isExpiry) {
        _expiry = picked;
      } else {
        _date = picked;
      }
    });
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final navigator = Navigator.of(context);
    final double total = double.tryParse(_totalCtrl.text.trim()) ?? 0;
    final Receipt receipt = Receipt(
      id: receiptId,
      storeName: _storeCtrl.text.trim(),
      date: _date,
      total: total,
      currency: _currency,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      imagePath: _imagePath,
      extractedText: _extractedText,
      expiryDate: _expiry,
    );
    final add = ref.read(addReceiptUseCaseProviderOverride);
    await add(receipt);
    if (mounted) navigator.pop();
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
      if (result.storeName != null) _storeCtrl.text = result.storeName!;
      if (result.total != null) _totalCtrl.text = result.total!.toStringAsFixed(2);
      if (result.date != null) {
        _date = result.date!;
        _dateCtrl.text = DateFormat.yMMMd().format(_date);
      }
      _extractedText =
          'Store: ${result.storeName ?? '-'}\nDate: ${result.date != null ? DateFormat.yMMMd().format(result.date!) : '-'}\nTotal: ${result.total?.toStringAsFixed(2) ?? '-'}\n\nRaw Text:\n${result.rawText ?? ''}';
    });
  }

  Future<void> _processImageFile(File imageFile) async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final uploadResult = await _uploadFileToStorage(fileToProcess);
    if (uploadResult == null) {
      throw Exception('File upload failed.');
    }

    final ocr = ref.read(ocrServiceProvider);
    // The GCS path is the path within the bucket, without the gs://<bucket-name>/ prefix
    final gcsPath = Uri.parse(uploadResult.gcsUri).path.substring(1);
    final result = await ocr.parseImage(gcsPath);
    _handleOcrResult(result, uploadedUrl: uploadResult.downloadUrl);
  }

  Future<void> _processAndUploadFile(File file) async {
    setState(() => _isLoading = true);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      if (file.path.toLowerCase().endsWith('.pdf')) {
        // It's a PDF. Try to extract text first.
        PDFDoc? pdfDoc;
        String extractedPdfText = '';
        try {
          pdfDoc = await PDFDoc.fromFile(file);
          extractedPdfText = await pdfDoc.text;
        } finally {
          await pdfDoc?.close();
        }

        // Heuristic to decide if it's a text-based PDF.
        // A small amount of text might just be a header on a scanned image.
        if (extractedPdfText.trim().length > 20) {
          debugPrint("Detected text-based PDF. Processing locally.");
          final uploadResult = await _uploadFileToStorage(file);
          if (uploadResult == null) {
            throw Exception('PDF upload failed.');
          }

          // Parse text locally using the shared parser functions
          final storeName = extractStoreName(extractedPdfText);
          final date = extractDate(extractedPdfText);
          final total = extractTotal(extractedPdfText);

          final ocrResult = OcrResult(
            storeName: storeName,
            date: date,
            total: total,
            rawText: extractedPdfText,
          );

          _handleOcrResult(ocrResult, uploadedUrl: uploadResult.downloadUrl);
        } else {
          // Scanned/Image-based PDF path. Convert to image and use Vision.
          debugPrint("Detected image-based PDF, converting to image.");
          final bool? proceed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Scanned PDF Detected'),
              content: const Text(
                  'This appears to be a scanned PDF. To extract data, the first page will be converted to an image and processed. Continue?'),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
              ],
            ),
          );

          if (proceed != true) {
            setState(() => _isLoading = false); // User cancelled
            return;
          }

          final doc = await PdfDocument.openFile(file.path);
          final page = await doc.getPage(1);
          const double scale = 2.0;
          final pageImage = await page.render(width: page.width * scale, height: page.height * scale);
          await page.close();
          await doc.close();

          if (pageImage == null) throw Exception("Failed to render PDF page.");

          final tempDir = await getTemporaryDirectory();
          final tempFileName = '${receiptId}_${DateTime.now().millisecondsSinceEpoch}.jpg';
          final imageFile = File(path.join(tempDir.path, tempFileName));
          await imageFile.writeAsBytes(pageImage.bytes);

          await _processImageFile(imageFile);
        }
      } else {
        // It's an image file, process as before.
        await _processImageFile(file);
      }
  } catch (e) {
    debugPrint("Error processing file: $e");
    scaffoldMessenger.showSnackBar(const SnackBar(
        content: Text('Could not process file. Please try again.')));
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



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add Receipt')),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (_imagePath != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Selected image: ${_imagePath}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                TextFormField(
                  controller: _storeCtrl,
                  decoration: const InputDecoration(labelText: 'Store name'),
                  validator: (String? v) => v == null || v.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dateCtrl..text = DateFormat.yMMMd().format(_date),
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Date'),
                  onTap: () => _pickDate(_dateCtrl),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : () => _pickImage(fromCamera: true),
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
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Total amount'),
                        validator: (String? v) => (double.tryParse(v ?? '') == null) ? 'Enter valid number' : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _currency,
                      onChanged: (String? v) => setState(() => _currency = v ?? _currency),
                      items: AppConstants.supportedCurrencies
                          .map((String c) => DropdownMenuItem<String>(value: c, child: Text(c)))
                          .toList(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _expiryCtrl,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Expiry date (optional)'),
                  onTap: () => _pickDate(_expiryCtrl, isExpiry: true),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: const InputDecoration(labelText: 'Notes (optional)'),
                  maxLines: 3,
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _submit,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Save'),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }
}
