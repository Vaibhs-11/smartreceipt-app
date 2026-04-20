import 'dart:io';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/export/export_context.dart';
import 'package:receiptnest/domain/services/insights_engine.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ReimbursementPdfBuilder {
  const ReimbursementPdfBuilder({
    this.insightsEngine = const InsightsEngine(),
  });

  final InsightsEngine insightsEngine;

  Future<File> build({
    required List<Receipt> receipts,
    required ExportContext context,
    required Directory directory,
  }) async {
    final document = PdfDocument();
    final fontData = await rootBundle.load('assets/fonts/NotoSans-Regular.ttf');
    final fontBytes = fontData.buffer.asUint8List();
    final titleFont = PdfTrueTypeFont(fontBytes, 20, style: PdfFontStyle.bold);
    final headingFont =
        PdfTrueTypeFont(fontBytes, 14, style: PdfFontStyle.bold);
    final bodyFont = PdfTrueTypeFont(fontBytes, 10);
    final boldBodyFont =
        PdfTrueTypeFont(fontBytes, 10, style: PdfFontStyle.bold);
    final page = document.pages.add();
    final pageWidth = page.getClientSize().width;
    var result = PdfTextElement(
      text: context.title?.trim().isNotEmpty == true
          ? context.title!.trim()
          : 'Reimbursement Report',
      font: titleFont,
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, 0, pageWidth, 30),
    );

    result = _drawMetadata(
      page: result?.page ?? page,
      top: (result?.bounds.bottom ?? 0) + 8,
      pageWidth: pageWidth,
      font: bodyFont,
      context: context,
      receipts: receipts,
    );

    result = _drawSummary(
      page: result.page,
      top: result.bounds.bottom + 18,
      pageWidth: pageWidth,
      headingFont: headingFont,
      bodyFont: bodyFont,
      receipts: receipts,
    );

    result = _drawCategoryBreakdown(
      page: result.page,
      top: result.bounds.bottom + 18,
      pageWidth: pageWidth,
      headingFont: headingFont,
      bodyFont: bodyFont,
      boldBodyFont: boldBodyFont,
      receipts: receipts,
    );

    _drawAuditList(
      page: result.page,
      top: result.bounds.bottom + 18,
      pageWidth: pageWidth,
      headingFont: headingFont,
      bodyFont: bodyFont,
      receipts: receipts,
    );

    final bytes = document.saveSync();
    document.dispose();

    final file = File('${directory.path}/report.pdf');
    return file.writeAsBytes(bytes, flush: true);
  }

  PdfLayoutResult _drawMetadata({
    required PdfPage page,
    required double top,
    required double pageWidth,
    required PdfFont font,
    required ExportContext context,
    required List<Receipt> receipts,
  }) {
    final lines = <String>[
      if ((context.dateRangeLabel ?? '').trim().isNotEmpty)
        'Date range: ${context.dateRangeLabel!.trim()}'
      else if (receipts.isNotEmpty)
        'Date range: ${_deriveDateRange(receipts)}',
      'Export date: ${DateFormat.yMMMd().format(DateTime.now())}',
    ];

    return PdfTextElement(
      text: lines.join('\n'),
      font: font,
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, top, pageWidth, 40),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    )!;
  }

  PdfLayoutResult _drawSummary({
    required PdfPage page,
    required double top,
    required double pageWidth,
    required PdfFont headingFont,
    required PdfFont bodyFont,
    required List<Receipt> receipts,
  }) {
    final heading = PdfTextElement(
      text: 'Summary',
      font: headingFont,
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, top, pageWidth, 20),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    )!;

    final grid = PdfGrid();
    grid.columns.add(count: 2);
    final row1 = grid.rows.add();
    row1.cells[0].value = 'Total spend';
    row1.cells[1].value = _formatReceiptTotalsMultiline(receipts);
    final row2 = grid.rows.add();
    row2.cells[0].value = 'Total receipts';
    row2.cells[1].value = receipts.length.toString();
    grid.style.font = bodyFont;

    return grid.draw(
      page: heading.page,
      bounds: Rect.fromLTWH(0, heading.bounds.bottom + 8, pageWidth, 0),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    )!;
  }

  PdfLayoutResult _drawCategoryBreakdown({
    required PdfPage page,
    required double top,
    required double pageWidth,
    required PdfFont headingFont,
    required PdfFont bodyFont,
    required PdfFont boldBodyFont,
    required List<Receipt> receipts,
  }) {
    var result = PdfTextElement(
      text: 'Category breakdown',
      font: headingFont,
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, top, pageWidth, 20),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    )!;

    for (final currencyGroup in _buildCurrencyCategoryGroups(receipts)) {
      result = PdfTextElement(
        text:
            '${currencyGroup.currency} total: ${_formatCurrency(currencyGroup.currency, currencyGroup.totalAmount)}',
        font: boldBodyFont,
      ).draw(
        page: result.page,
        bounds: Rect.fromLTWH(0, result.bounds.bottom + 10, pageWidth, 20),
        format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
      )!;

      for (final categoryGroup in currencyGroup.categories) {
        result = PdfTextElement(
          text:
              '${categoryGroup.category} • ${_formatCurrency(currencyGroup.currency, categoryGroup.totalAmount)}',
          font: boldBodyFont,
        ).draw(
          page: result.page,
          bounds: Rect.fromLTWH(0, result.bounds.bottom + 8, pageWidth, 20),
          format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
        )!;

        final grid = PdfGrid();
        grid.columns.add(count: 4);
        grid.columns[0].width = 72;
        grid.columns[1].width = 120;
        grid.columns[3].width = 72;
        grid.columns[2].width =
            (pageWidth - grid.columns[0].width - grid.columns[1].width - grid.columns[3].width)
                .clamp(0, pageWidth)
                .toDouble();
        final header = grid.headers.add(1)[0];
        header.cells[0].value = 'Date';
        header.cells[1].value = 'Merchant';
        header.cells[2].value = 'Item';
        header.cells[3].value = 'Amount';
        final amountAlignment =
            PdfStringFormat(alignment: PdfTextAlignment.right);
        header.cells[3].style.stringFormat = amountAlignment;
        for (final item in categoryGroup.items) {
          final row = grid.rows.add();
          row.cells[0].value = DateFormat('yyyy-MM-dd').format(item.date);
          row.cells[1].value = item.merchant;
          row.cells[2].value = item.name;
          row.cells[3].value = item.amount.toStringAsFixed(2);
          row.cells[3].style.stringFormat = amountAlignment;
        }
        grid.style.font = bodyFont;
        result = grid.draw(
          page: result.page,
          bounds: Rect.fromLTWH(0, result.bounds.bottom + 6, pageWidth, 0),
          format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
        )!;
      }
    }

    return result;
  }

  PdfLayoutResult _drawAuditList({
    required PdfPage page,
    required double top,
    required double pageWidth,
    required PdfFont headingFont,
    required PdfFont bodyFont,
    required List<Receipt> receipts,
  }) {
    final heading = PdfTextElement(
      text: 'Receipt audit list',
      font: headingFont,
    ).draw(
      page: page,
      bounds: Rect.fromLTWH(0, top, pageWidth, 20),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    )!;

    final sortedReceipts = List<Receipt>.from(receipts)
      ..sort((a, b) => a.date.compareTo(b.date));
    final grid = PdfGrid();
    grid.columns.add(count: 4);
    final header = grid.headers.add(1)[0];
    header.cells[0].value = 'Date';
    header.cells[1].value = 'Merchant';
    header.cells[2].value = 'Amount';
    header.cells[3].value = 'Currency';
    for (final receipt in sortedReceipts) {
      final row = grid.rows.add();
      row.cells[0].value = DateFormat('yyyy-MM-dd').format(receipt.date);
      row.cells[1].value = receipt.storeName.trim();
      row.cells[2].value = receipt.total.toStringAsFixed(2);
      row.cells[3].value = _normalizeCurrency(receipt.currency);
    }
    grid.style.font = bodyFont;
    return grid.draw(
      page: heading.page,
      bounds: Rect.fromLTWH(0, heading.bounds.bottom + 8, pageWidth, 0),
      format: PdfLayoutFormat(layoutType: PdfLayoutType.paginate),
    )!;
  }

  String _deriveDateRange(List<Receipt> receipts) {
    if (receipts.isEmpty) {
      return 'N/A';
    }
    final sorted = List<Receipt>.from(receipts)
      ..sort((a, b) => a.date.compareTo(b.date));
    final start = DateFormat.yMMMd().format(sorted.first.date);
    final end = DateFormat.yMMMd().format(sorted.last.date);
    return '$start - $end';
  }

  String _formatReceiptTotalsMultiline(List<Receipt> receipts) {
    final totals = <String, double>{};
    for (final receipt in receipts) {
      final currency = _normalizeCurrency(receipt.currency);
      totals.update(currency, (value) => value + receipt.total,
          ifAbsent: () => receipt.total);
    }
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries
        .map((entry) =>
            '${entry.key} ${_formatCurrency(entry.key, entry.value)}')
        .join('\n');
  }

  String _formatCurrency(String currency, double amount) {
    try {
      return NumberFormat.simpleCurrency(name: currency).format(amount);
    } catch (_) {
      return '$currency ${amount.toStringAsFixed(2)}';
    }
  }

  String _normalizeCurrency(String currency) {
    final normalized = currency.trim();
    return normalized.isEmpty ? 'Unknown' : normalized;
  }

  List<_CurrencyCategoryGroup> _buildCurrencyCategoryGroups(
      List<Receipt> receipts) {
    final grouped = <String, Map<String, List<_CategoryLineItem>>>{};
    for (final receipt in receipts) {
      final currency =
          receipt.currency.trim().isEmpty ? 'Unknown' : receipt.currency.trim();
      final categoryGroups = grouped.putIfAbsent(
          currency, () => <String, List<_CategoryLineItem>>{});

      for (final item in receipt.items) {
        final amount = item.price;
        final name = item.name.trim();
        if (amount == null || amount <= 0 || name.isEmpty) {
          continue;
        }

        final category = insightsEngine.resolveEffectiveCategory(
          item: item,
          isCollectionQuery: true,
        );
        categoryGroups.putIfAbsent(category, () => <_CategoryLineItem>[]).add(
              _CategoryLineItem(
                date: receipt.date,
                merchant: receipt.storeName.trim(),
                name: name,
                amount: amount,
              ),
            );
      }
    }

    final currencies = grouped.entries.map((currencyEntry) {
      final categories = currencyEntry.value.entries.map((categoryEntry) {
        final items = categoryEntry.value
          ..sort((a, b) => a.date.compareTo(b.date));
        final totalAmount = items.fold<double>(
          0,
          (sum, item) => sum + item.amount,
        );
        return _CategoryGroup(
          category: categoryEntry.key,
          totalAmount: totalAmount,
          items: items,
        );
      }).toList()
        ..sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

      final totalAmount = categories.fold<double>(
        0,
        (sum, category) => sum + category.totalAmount,
      );
      return _CurrencyCategoryGroup(
        currency: currencyEntry.key,
        totalAmount: totalAmount,
        categories: categories,
      );
    }).toList()
      ..sort((a, b) => a.currency.compareTo(b.currency));

    return currencies;
  }
}

class _CurrencyCategoryGroup {
  const _CurrencyCategoryGroup({
    required this.currency,
    required this.totalAmount,
    required this.categories,
  });

  final String currency;
  final double totalAmount;
  final List<_CategoryGroup> categories;
}

class _CategoryGroup {
  const _CategoryGroup({
    required this.category,
    required this.totalAmount,
    required this.items,
  });

  final String category;
  final double totalAmount;
  final List<_CategoryLineItem> items;
}

class _CategoryLineItem {
  const _CategoryLineItem({
    required this.date,
    required this.merchant,
    required this.name,
    required this.amount,
  });

  final DateTime date;
  final String merchant;
  final String name;
  final double amount;
}
