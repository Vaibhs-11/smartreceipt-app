import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/data/services/export/on_device_receipt_export_service.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/export/builders/image_export_collector.dart';
import 'package:receiptnest/domain/services/export/export_context.dart';
import 'package:receiptnest/domain/services/export/export_engine.dart';
import 'package:receiptnest/domain/services/export/export_file_namer.dart';

void main() {
  group('OnDeviceExportEngine', () {
    late Directory tempRoot;
    late OnDeviceExportEngine engine;
    late _FakeExportReceiptFileResolver resolver;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('export_engine_test');
      resolver = _FakeExportReceiptFileResolver(
        files: <String, _FakeResolvedFile>{
          'r1': _FakeResolvedFile(
            sourcePath: 'receipts/processed.jpg',
            bytes: utf8.encode('image-1'),
          ),
          'r2': _FakeResolvedFile(
            sourcePath: 'receipts/original.pdf',
            bytes: utf8.encode('pdf-2'),
          ),
          'abc-123': _FakeResolvedFile(
            sourcePath: 'receipts/custom.jpg',
            bytes: utf8.encode('image-3'),
          ),
        },
      );
      engine = OnDeviceExportEngine(
        workingDirectoryProvider: _TestWorkingDirectoryProvider(tempRoot),
        imageExportCollector: ImageExportCollector(
          fileResolver: resolver,
          fileNamer: const ExportFileNamer(),
        ),
        clock: () => DateTime.utc(2026, 4, 16, 10, 30),
      );
    });

    tearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });

    test('collection export creates zip with pdf csv and images', () async {
      final result = await engine.generate(
        receipts: <Receipt>[
          _receipt(
            id: 'r1',
            merchant: 'Office Works',
            date: DateTime.utc(2026, 4, 2),
            total: 23.4,
            items: const <ReceiptItem>[
              ReceiptItem(
                name: 'Notebook',
                price: 23.4,
                category: 'Stationery',
                collectionCategory: 'Shopping',
              ),
            ],
          ),
          _receipt(
            id: 'r2',
            merchant: 'Airline',
            date: DateTime.utc(2026, 4, 5),
            total: 199.99,
            items: const <ReceiptItem>[
              ReceiptItem(
                name: 'Flight',
                price: 199.99,
                category: 'Travel',
              ),
            ],
          ),
        ],
        context: const ExportContext.collection(title: 'April Trip'),
      );

      final archive =
          ZipDecoder().decodeBytes(await File(result.zipPath).readAsBytes());
      final names = archive.files.map((file) => file.name).toList()..sort();

      expect(names, contains('report.pdf'));
      expect(names, contains('receipts.csv'));
      expect(
        names,
        contains('images/2026-04-02_office_works_23.40_r1.jpg'),
      );
      expect(
        names,
        contains('images/2026-04-05_airline_199.99_r2.pdf'),
      );
    });

    test('search export creates zip with images only', () async {
      final result = await engine.generate(
        receipts: <Receipt>[
          _receipt(id: 'r1', merchant: 'Cafe', total: 8.5),
        ],
        context: const ExportContext.search(title: 'tax evidence'),
      );

      final archive =
          ZipDecoder().decodeBytes(await File(result.zipPath).readAsBytes());
      final names = archive.files.map((file) => file.name).toList();

      expect(names, hasLength(1));
      expect(names.single, 'images/2026-04-16_cafe_8.50_r1.jpg');
    });

    test('filenames are human readable sortable and unique', () async {
      final result = await engine.generate(
        receipts: <Receipt>[
          _receipt(
            id: 'abc-123',
            merchant: 'My Store Pty. Ltd.',
            date: DateTime.utc(2026, 1, 9),
            total: 10,
          ),
        ],
        context: const ExportContext.search(title: 'search'),
      );

      final archive =
          ZipDecoder().decodeBytes(await File(result.zipPath).readAsBytes());
      final imageName = archive.files.single.name;
      expect(imageName, 'images/2026-01-09_my_store_pty_ltd_10.00_abc_123.jpg');
    });

    test('export respects receipts list passed from caller', () async {
      final result = await engine.generate(
        receipts: <Receipt>[
          _receipt(id: 'r2', merchant: 'Subset', total: 12.0),
        ],
        context: const ExportContext.search(title: 'subset'),
      );

      final archive =
          ZipDecoder().decodeBytes(await File(result.zipPath).readAsBytes());
      final names = archive.files.map((file) => file.name).toList();
      expect(names, contains('images/2026-04-16_subset_12.00_r2.pdf'));
      expect(names.join(','), isNot(contains('r1')));
    });

    test('missing images do not crash whole export', () async {
      final result = await engine.generate(
        receipts: <Receipt>[
          _receipt(id: 'r1', merchant: 'Valid', total: 7.5),
          _receipt(id: 'missing', merchant: 'Missing', total: 3.0),
        ],
        context: const ExportContext.search(title: 'partial'),
      );

      expect(result.exportedFileCount, 1);
      expect(result.skippedReceiptIds, <String>['missing']);

      final archive =
          ZipDecoder().decodeBytes(await File(result.zipPath).readAsBytes());
      expect(archive.files.map((file) => file.name), <String>[
        'images/2026-04-16_valid_7.50_r1.jpg',
      ]);
    });
  });

  test('share launcher is invoked after successful export', () async {
    final tempRoot = await Directory.systemTemp.createTemp('export_share_test');
    final engine = OnDeviceExportEngine(
      workingDirectoryProvider: _TestWorkingDirectoryProvider(tempRoot),
      imageExportCollector: ImageExportCollector(
        fileResolver: _FakeExportReceiptFileResolver(
          files: <String, _FakeResolvedFile>{
            'r1': _FakeResolvedFile(
              sourcePath: 'receipts/sample.jpg',
              bytes: utf8.encode('image-1'),
            ),
          },
        ),
        fileNamer: const ExportFileNamer(),
      ),
      clock: () => DateTime.utc(2026, 4, 16, 10, 30),
    );
    final shareLauncher = _FakeShareLauncher();
    final service = OnDeviceReceiptExportService(
      exportEngine: engine,
      shareLauncher: shareLauncher,
    );

    final result = await service.exportAndShare(
      receipts: <Receipt>[_receipt(id: 'r1', merchant: 'Cafe')],
      context: const ExportContext.search(title: 'tax evidence'),
    );

    expect(shareLauncher.sharedPaths, <String>[result.zipPath]);
    expect(shareLauncher.sharedFileNames, <String>[result.fileName]);

    if (await tempRoot.exists()) {
      await tempRoot.delete(recursive: true);
    }
  });
}

Receipt _receipt({
  required String id,
  String merchant = 'Merchant',
  DateTime? date,
  double total = 10,
  String currency = 'AUD',
  List<ReceiptItem> items = const <ReceiptItem>[
    ReceiptItem(name: 'Item', price: 10, category: 'General'),
  ],
}) {
  return Receipt(
    id: id,
    storeName: merchant,
    date: date ?? DateTime.utc(2026, 4, 16),
    total: total,
    currency: currency,
    items: items,
  );
}

class _TestWorkingDirectoryProvider implements ExportWorkingDirectoryProvider {
  _TestWorkingDirectoryProvider(this.root);

  final Directory root;
  var _counter = 0;

  @override
  Future<Directory> createWorkingDirectory(ExportContext context) async {
    final directory = Directory('${root.path}/run_${_counter++}');
    return directory.create(recursive: true);
  }
}

class _FakeExportReceiptFileResolver implements ExportReceiptFileResolver {
  _FakeExportReceiptFileResolver({
    required this.files,
  });

  final Map<String, _FakeResolvedFile> files;

  @override
  Future<ResolvedExportReceiptFile?> resolve(Receipt receipt) async {
    return files[receipt.id];
  }
}

class _FakeResolvedFile extends ResolvedExportReceiptFile {
  _FakeResolvedFile({
    required this.sourcePath,
    required this.bytes,
  });

  @override
  final String sourcePath;

  final List<int> bytes;

  @override
  String? get contentType => null;

  @override
  Future<void> writeTo(File destination) async {
    await destination.writeAsBytes(bytes, flush: true);
  }
}

class _FakeShareLauncher implements ExportShareLauncher {
  final List<String> sharedPaths = <String>[];
  final List<String> sharedFileNames = <String>[];

  @override
  Future<void> share({
    required String path,
    required String fileName,
  }) async {
    sharedPaths.add(path);
    sharedFileNames.add(fileName);
  }
}
