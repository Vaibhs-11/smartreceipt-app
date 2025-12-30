import 'dart:async';

import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class LocalReceiptRepository implements ReceiptRepository {
  LocalReceiptRepository();

  static final List<Receipt> _receipts = <Receipt>[];

  @override
  Future<void> addReceipt(Receipt receipt) async {
    final sanitized = receipt.copyWith(
      items: sanitizeReceiptItems(receipt.items),
    );
    _receipts.add(sanitized);
  }

  @override
  Future<void> deleteReceipt(String id) async {
    _receipts.removeWhere((Receipt r) => r.id == id);
  }

  Future<List<Receipt>> getAllReceipts() async {
    // Simulate small latency for UX parity
    await Future<void>.delayed(const Duration(milliseconds: 80));
    return List<Receipt>.unmodifiable(_receipts);
  }

  @override
  Future<Receipt?> getReceiptById(String id) async {
    try {
      return _receipts.firstWhere((Receipt r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> updateReceipt(Receipt receipt) async {
    final sanitized = receipt.copyWith(
      items: sanitizeReceiptItems(receipt.items),
    );
    final int index = _receipts.indexWhere((Receipt r) => r.id == sanitized.id);
    if (index >= 0) {
      _receipts[index] = sanitized;
    }
  }

  @override
  Future<int> getReceiptCount() async {
    return _receipts.length;
  }

  @override
  Future<List<Receipt>> getReceipts() {
    return getAllReceipts();
  }
}
