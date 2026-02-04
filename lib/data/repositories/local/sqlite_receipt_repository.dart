import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/repositories/receipt_repository.dart';

class SqliteReceiptRepository implements ReceiptRepository {
  SqliteReceiptRepository();

  static Future<Database> _openDb() async {
    final String dir = (await getApplicationDocumentsDirectory()).path;
    final String dbPath = p.join(dir, 'smartreceipt.db');
    return openDatabase(
      dbPath,
      password: 'smartreceipt_dev',
      version: 4, // schema now tracks processed/original image metadata
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
          metadata TEXT
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
          await db.execute('ALTER TABLE receipts ADD COLUMN metadata TEXT;');
        }
      },
    );
  }

  static final Future<Database> _dbFuture = _openDb();

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

  Map<String, Object?> _toDbMap(Receipt r) => <String, Object?>{
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
      };

  Receipt _fromDbMap(Map<String, Object?> map) {
    final List<String> tags = (map['tags'] as String?) != null
        ? (jsonDecode(map['tags']! as String) as List<dynamic>).cast<String>()
        : <String>[];
    Map<String, Object?>? metadata;
    final metadataRaw = map['metadata'] as String?;
    if (metadataRaw != null) {
      try {
        final decoded = jsonDecode(metadataRaw);
        if (decoded is Map) {
          metadata = Map<String, Object?>.from(decoded as Map);
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
    );
  }
}
