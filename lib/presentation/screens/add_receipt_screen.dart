import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:smartreceipt/core/constants/app_constants.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:uuid/uuid.dart';

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
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isExpiry ? (_expiry ?? DateTime.now()) : _date,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
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
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
    if (mounted) Navigator.of(context).pop();
  }

  Future<String?> _uploadFileToStorage(File file) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint("Cannot upload file, user not logged in.");
      return null;
    }
    try {
      final fileName = file.path.split('/').last;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child("receipts")
          .child(user.uid)
          .child(receiptId)
          .child(fileName);

      await storageRef.putFile(file);
      return await storageRef.getDownloadURL();
    } catch (e) {
      debugPrint("Upload failed: $e");
      return null;
    }
  }

  void _handleOcrResult(OcrResult result, {String? uploadedUrl}) {
    if (!mounted) return;
    setState(() {
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
          'Store: ${result.storeName ?? '-'}\nDate: ${result.date != null ? DateFormat.yMMMd().format(result.date!) : '-'}\nTotal: ${result.total?.toStringAsFixed(2) ?? '-'}';
    });
  }

  Future<void> _pickImage({required bool fromCamera}) async {
    final picker = ImagePicker();
    final XFile? file = await (fromCamera
        ? picker.pickImage(source: ImageSource.camera)
        : picker.pickImage(source: ImageSource.gallery));
    if (file == null) return;

    // TODO: Show a loading indicator
    final uploadedUrl = await _uploadFileToStorage(File(file.path));
    final ocr = ref.read(ocrServiceProvider);
    final result = await ocr.parseImage(file.path);
    // TODO: Hide loading indicator

    _handleOcrResult(result, uploadedUrl: uploadedUrl);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
    );

    if (result == null || result.files.single.path == null) return;
    final file = File(result.files.single.path!);

    // TODO: Show a loading indicator
    final uploadedUrl = await _uploadFileToStorage(file);
    final ocr = ref.read(ocrServiceProvider);
    final ocrResult = file.path.toLowerCase().endsWith('.pdf')
        ? await ocr.parsePdf(file.path)
        : await ocr.parseImage(file.path);
    // TODO: Hide loading indicator

    _handleOcrResult(ocrResult, uploadedUrl: uploadedUrl);
  }
Future<void> _showUploadOptions(BuildContext context) async {
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
      body: Form(
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
                    onPressed: () => _pickImage(fromCamera: true),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('Capture'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showUploadOptions(context),
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
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
