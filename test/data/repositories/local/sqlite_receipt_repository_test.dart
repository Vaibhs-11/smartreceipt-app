import 'package:flutter_test/flutter_test.dart';
import 'package:receiptnest/data/repositories/local/sqlite_receipt_repository.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

void main() {
  group('SqliteReceiptRepository mapping', () {
    test('collectionId persists through db map conversion', () {
      final receipt = Receipt(
        id: 'receipt-1',
        storeName: 'Store',
        date: DateTime.utc(2026, 1, 1),
        total: 12.34,
        currency: 'AUD',
        collectionId: 'collection-1',
        tags: const <String>['food'],
      );

      final map = SqliteReceiptRepository.receiptToDbMap(receipt);
      final restored = SqliteReceiptRepository.receiptFromDbMap(map);

      expect(map['collectionId'], 'collection-1');
      expect(restored.collectionId, 'collection-1');
      expect(restored.storeName, 'Store');
      expect(restored.total, 12.34);
    });
  });

  group('SqliteReceiptRepository migration helpers', () {
    test('detects existing columns safely', () {
      final tableInfo = <Map<String, Object?>>[
        <String, Object?>{'name': 'id'},
        <String, Object?>{'name': 'collectionId'},
      ];

      expect(
        SqliteReceiptRepository.hasColumn(tableInfo, 'collectionId'),
        isTrue,
      );
      expect(SqliteReceiptRepository.hasColumn(tableInfo, 'metadata'), isFalse);
    });

    test('only adds collectionId when missing', () async {
      final db = _FakeDatabaseExecutor(
        tableInfo: <Map<String, Object?>>[
          <String, Object?>{'name': 'id'},
          <String, Object?>{'name': 'storeName'},
        ],
      );

      await SqliteReceiptRepository.ensureColumnExists(
        db,
        tableName: 'receipts',
        columnName: 'collectionId',
        columnDefinition: 'collectionId TEXT',
      );

      expect(db.executedStatements,
          <String>['ALTER TABLE receipts ADD COLUMN collectionId TEXT;']);
      expect(
        SqliteReceiptRepository.hasColumn(db.tableInfo, 'collectionId'),
        isTrue,
      );
    });

    test('skips alter table when collectionId already exists', () async {
      final db = _FakeDatabaseExecutor(
        tableInfo: <Map<String, Object?>>[
          <String, Object?>{'name': 'id'},
          <String, Object?>{'name': 'collectionId'},
        ],
      );

      await SqliteReceiptRepository.ensureColumnExists(
        db,
        tableName: 'receipts',
        columnName: 'collectionId',
        columnDefinition: 'collectionId TEXT',
      );

      expect(db.executedStatements, isEmpty);
    });
  });
}

class _FakeDatabaseExecutor extends Fake implements DatabaseExecutor {
  _FakeDatabaseExecutor({
    required List<Map<String, Object?>> tableInfo,
  }) : tableInfo = List<Map<String, Object?>>.from(tableInfo);

  final List<String> executedStatements = <String>[];
  final List<Map<String, Object?>> tableInfo;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    executedStatements.add(sql);
    if (sql == 'ALTER TABLE receipts ADD COLUMN collectionId TEXT;') {
      tableInfo.add(<String, Object?>{'name': 'collectionId'});
    }
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) async {
    if (sql == 'PRAGMA table_info(receipts)') {
      return List<Map<String, Object?>>.from(tableInfo);
    }
    return <Map<String, Object?>>[];
  }
}
