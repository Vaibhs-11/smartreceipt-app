import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
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
  String _currency = AppConstants.supportedCurrencies.first;
  DateTime _date = DateTime.now();
  DateTime? _expiry;

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
      id: const Uuid().v4(),
      storeName: _storeCtrl.text.trim(),
      date: _date,
      total: total,
      currency: _currency,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      expiryDate: _expiry,
    );
    final add = ref.read(addReceiptUseCaseProviderOverride);
    await add(receipt);
    if (mounted) Navigator.of(context).pop();
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


