import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/domain/repositories/receipt_repository.dart';

class SqliteReceiptRepository implements ReceiptRepository {
  SqliteReceiptRepository();

  static Future<Database> _openDb() async {
    final String dir = (await getApplicationDocumentsDirectory()).path;
    final String dbPath = p.join(dir, 'smartreceipt.db');
    return openDatabase(
      dbPath,
      password: 'smartreceipt_dev',
      version: 1,
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
          expiryDate TEXT
        );
        ''');
      },
    );
  }

  static final Future<Database> _dbFuture = _openDb();

  @override
  Future<void> addReceipt(Receipt receipt) async {
    final Database db = await _dbFuture;
    await db.insert('receipts', _toDbMap(receipt), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> deleteReceipt(String id) async {
    final Database db = await _dbFuture;
    await db.delete('receipts', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  @override
  Future<List<Receipt>> getAllReceipts() async {
    final Database db = await _dbFuture;
    final List<Map<String, Object?>> rows = await db.query('receipts', orderBy: 'date DESC');
    return rows.map(_fromDbMap).toList();
  }

  @override
  Future<Receipt?> getReceiptById(String id) async {
    final Database db = await _dbFuture;
    final List<Map<String, Object?>> rows =
        await db.query('receipts', where: 'id = ?', whereArgs: <Object?>[id], limit: 1);
    if (rows.isEmpty) return null;
    return _fromDbMap(rows.first);
  }

  @override
  Future<void> updateReceipt(Receipt receipt) async {
    final Database db = await _dbFuture;
    await db.update('receipts', _toDbMap(receipt), where: 'id = ?', whereArgs: <Object?>[receipt.id]);
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
        'expiryDate': r.expiryDate?.toIso8601String(),
      };

  Receipt _fromDbMap(Map<String, Object?> map) {
    final List<String> tags = (map['tags'] as String?) != null
        ? (jsonDecode(map['tags']! as String) as List<dynamic>).cast<String>()
        : <String>[];
    return Receipt(
      id: map['id']! as String,
      storeName: map['storeName']! as String,
      date: DateTime.parse(map['date']! as String),
      total: (map['total']! as num).toDouble(),
      currency: map['currency']! as String,
      notes: map['notes'] as String?,
      tags: tags,
      imagePath: map['imagePath'] as String?,
      expiryDate: (map['expiryDate'] as String?) != null
          ? DateTime.parse(map['expiryDate']! as String)
          : null,
    );
  }
}


