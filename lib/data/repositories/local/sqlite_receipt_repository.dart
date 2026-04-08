import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';

class SqliteReceiptRepository implements ReceiptRepository {
  SqliteReceiptRepository({
    Future<Database> Function()? databaseOpener,
  }) : _dbFuture = (databaseOpener ?? _openDb)();

  final Future<Database> _dbFuture;

  static Future<Database> _openDb() async {
    final String dir = (await getApplicationDocumentsDirectory()).path;
    final String dbPath = p.join(dir, 'smartreceipt.db');
    return openDatabase(
      dbPath,
      password: 'smartreceipt_dev',
      version: 5, // schema now tracks trip linkage metadata
      onCreate: (Database db, int version) async {
        await db.execute('''
        CREATE TABLE receipts (
          id TEXT PRIMARY KEY,
          storeName TEXT NOT NULL,
          date TEXT NOT NULL,
          total REAL NOT NULL,
          currency TEXT NOT NULL,
          notes TEXT,
          tags TEXT,
          imagePath TEXT,
          originalImagePath TEXT,
          processedImagePath TEXT,
          imageProcessingStatus TEXT,
          extractedText TEXT,
          metadata TEXT,
          tripId TEXT
        );
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db
              .execute('ALTER TABLE receipts ADD COLUMN extractedText TEXT;');
        }
        if (oldVersion < 3) {
          await db.execute(
              'ALTER TABLE receipts ADD COLUMN originalImagePath TEXT;');
          await db.execute(
              'ALTER TABLE receipts ADD COLUMN processedImagePath TEXT;');
          await db.execute(
              'ALTER TABLE receipts ADD COLUMN imageProcessingStatus TEXT;');
        }
        if (oldVersion < 4) {
          await ensureColumnExists(
            db,
            tableName: 'receipts',
            columnName: 'metadata',
            columnDefinition: 'metadata TEXT',
          );
        }
        if (oldVersion < 5) {
          await ensureColumnExists(
            db,
            tableName: 'receipts',
            columnName: 'tripId',
            columnDefinition: 'tripId TEXT',
          );
        }
      },
    );
  }

  @visibleForTesting
  static Future<void> ensureColumnExists(
    DatabaseExecutor db, {
    required String tableName,
    required String columnName,
    required String columnDefinition,
  }) async {
    final tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
    if (_hasColumn(tableInfo, columnName)) {
      return;
    }

    await db.execute('ALTER TABLE $tableName ADD COLUMN $columnDefinition;');
  }

  @visibleForTesting
  static bool hasColumn(
    List<Map<String, Object?>> tableInfo,
    String columnName,
  ) {
    return _hasColumn(tableInfo, columnName);
  }

  @visibleForTesting
  static Map<String, Object?> receiptToDbMap(Receipt receipt) {
    return _toDbMap(receipt);
  }

  @visibleForTesting
  static Receipt receiptFromDbMap(Map<String, Object?> map) {
    return _fromDbMap(map);
  }

  @override
  Future<void> addReceipt(Receipt receipt) async {
    final Database db = await _dbFuture;
    final sanitized = receipt.copyWith(
      items: sanitizeReceiptItems(receipt.items),
    );
    await db.insert('receipts', _toDbMap(sanitized),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteReceipt(String id) async {
    final Database db = await _dbFuture;
    await db.delete('receipts', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<List<Receipt>> getAllReceipts() async {
    final Database db = await _dbFuture;
    final List<Map<String, Object?>> rows =
        await db.query('receipts', orderBy: 'date DESC');
    return rows.map(_fromDbMap).toList();
  }

  @override
  Future<Receipt?> getReceiptById(String id) async {
    final Database db = await _dbFuture;
    final List<Map<String, Object?>> rows = await db.query('receipts',
        where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromDbMap(rows.first);
  }

  @override
  Future<void> updateReceipt(Receipt receipt) async {
    final Database db = await _dbFuture;
    final sanitized = receipt.copyWith(
      items: sanitizeReceiptItems(receipt.items),
    );
    await db.update('receipts', _toDbMap(sanitized),
        where: 'id = ?', whereArgs: <Object?>[sanitized.id]);
  }

  @override
  Future<int> getReceiptCount() async {
    final Database db = await _dbFuture;
    final result = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM receipts'),
        ) ??
        0;
    return result;
  }

  @override
  Future<List<Receipt>> getReceipts() {
    return getAllReceipts();
  }

  static bool _hasColumn(
    List<Map<String, Object?>> tableInfo,
    String columnName,
  ) {
    return tableInfo.any((column) => column['name'] == columnName);
  }

  static Map<String, Object?> _toDbMap(Receipt r) => <String, Object?>{
        'id': r.id,
        'storeName': r.storeName,
        'date': r.date.toIso8601String(),
        'total': r.total,
        'currency': r.currency,
        'notes': r.notes,
        'tags': jsonEncode(r.tags),
        'imagePath': r.imagePath,
        'originalImagePath': r.originalImagePath,
        'processedImagePath': r.processedImagePath,
        'imageProcessingStatus': r.imageProcessingStatus,
        'extractedText': r.extractedText,
        'metadata': r.metadata != null ? jsonEncode(r.metadata) : null,
        'tripId': r.tripId,
      };

  static Receipt _fromDbMap(Map<String, Object?> map) {
    final List<String> tags = (map['tags'] as String?) != null
        ? (jsonDecode(map['tags']! as String) as List<dynamic>).cast<String>()
        : <String>[];
    Map<String, Object?>? metadata;
    final metadataRaw = map['metadata'] as String?;
    if (metadataRaw != null) {
      try {
        final decoded = jsonDecode(metadataRaw);
        if (decoded is Map) {
          metadata = Map<String, Object?>.from(decoded);
        }
      } catch (_) {
        metadata = null;
      }
    }
    return Receipt(
      id: map['id']! as String,
      storeName: map['storeName']! as String,
      date: DateTime.parse(map['date']! as String),
      total: (map['total']! as num).toDouble(),
      currency: map['currency']! as String,
      notes: map['notes'] as String?,
      tags: tags,
      imagePath: map['imagePath'] as String?,
      originalImagePath: map['originalImagePath'] as String?,
      processedImagePath: map['processedImagePath'] as String?,
      imageProcessingStatus: map['imageProcessingStatus'] as String?,
      extractedText: map['extractedText'] as String?,
      metadata: metadata,
      tripId: map['tripId'] as String?,
    );
  }
}
