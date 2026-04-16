import 'dart:math';

import 'package:intl/intl.dart';
import 'package:receiptnest/domain/entities/receipt.dart';

class ExportFileNamer {
  const ExportFileNamer();

  String buildReceiptFileName({
    required Receipt receipt,
    required String extension,
  }) {
    final date = _dateLabel(receipt);
    final merchant = _sanitizeSegment(receipt.storeName, fallback: 'merchant');
    final amount = receipt.total.toStringAsFixed(2);
    final receiptId = _sanitizeSegment(receipt.id, fallback: 'receipt');
    final safeExtension = _normalizeExtension(extension);
    return '${date}_${merchant}_${amount}_$receiptId.$safeExtension';
  }

  String buildArchiveFileName({
    required String? title,
    required String label,
    required DateTime timestamp,
  }) {
    final base = _sanitizeSegment(title, fallback: label);
    final datePart = DateFormat('yyyyMMdd_HHmmss').format(timestamp);
    return '${base}_$datePart.zip';
  }

  String _dateLabel(Receipt receipt) {
    try {
      return DateFormat('yyyy-MM-dd').format(receipt.date);
    } catch (_) {
      return 'undated';
    }
  }

  String _sanitizeSegment(String? value, {required String fallback}) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (normalized.isEmpty) {
      return fallback;
    }

    final buffer = StringBuffer();
    var lastWasUnderscore = false;
    for (final rune in normalized.runes) {
      final char = String.fromCharCode(rune);
      final isAlphaNumeric = RegExp(r'[a-z0-9]').hasMatch(char);
      if (isAlphaNumeric) {
        buffer.write(char);
        lastWasUnderscore = false;
        continue;
      }

      if (!lastWasUnderscore) {
        buffer.write('_');
        lastWasUnderscore = true;
      }
    }

    final collapsed = buffer.toString().replaceAll(RegExp(r'_+'), '_');
    final trimmed = collapsed.replaceAll(RegExp(r'^_+|_+$'), '');
    if (trimmed.isEmpty) {
      return fallback;
    }
    return trimmed.substring(0, min(trimmed.length, 64));
  }

  String _normalizeExtension(String extension) {
    final normalized = extension.trim().replaceFirst(RegExp(r'^\.+'), '');
    if (normalized.isEmpty) {
      return 'bin';
    }
    return normalized.toLowerCase();
  }
}
