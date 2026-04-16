import 'dart:io';

import 'package:flutter/material.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:receiptnest/data/services/export/on_device_receipt_export_service.dart';
import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/services/export/builders/image_export_collector.dart';
import 'package:receiptnest/domain/services/export/export_context.dart';
import 'package:receiptnest/domain/services/export/export_engine.dart';
import 'package:share_plus/share_plus.dart';

class SystemExportWorkingDirectoryProvider
    implements ExportWorkingDirectoryProvider {
  const SystemExportWorkingDirectoryProvider();

  @override
  Future<Directory> createWorkingDirectory(ExportContext context) async {
    final tempDir = await getTemporaryDirectory();
    final name =
        'receipt_export_${DateTime.now().microsecondsSinceEpoch.toString()}';
    return Directory(p.join(tempDir.path, name)).create(recursive: true);
  }
}

class OnDeviceExportReceiptFileResolver implements ExportReceiptFileResolver {
  const OnDeviceExportReceiptFileResolver({
    http.Client? httpClient,
  }) : _httpClient = httpClient;

  final http.Client? _httpClient;

  @override
  Future<ResolvedExportReceiptFile?> resolve(Receipt receipt) async {
    final sourcePath = _resolveSourcePath(receipt);
    if (sourcePath == null) {
      return null;
    }

    if (sourcePath.startsWith('http://') || sourcePath.startsWith('https://')) {
      return NetworkResolvedExportFile(
        sourcePath: sourcePath,
        client: _httpClient ?? http.Client(),
      );
    }

    if (!sourcePath.startsWith('file://') && !sourcePath.startsWith('/')) {
      try {
        final ref = FirebaseStorage.instance.ref(sourcePath);
        final downloadUrl = await ref.getDownloadURL();
        return NetworkResolvedExportFile(
          sourcePath: downloadUrl,
          client: _httpClient ?? http.Client(),
        );
      } catch (error) {
        // Fall back to local file handling if the Firebase path cannot be resolved.
      }
    }

    final normalizedPath = sourcePath.startsWith('file://')
        ? Uri.parse(sourcePath).toFilePath()
        : sourcePath;
    final localFile = File(normalizedPath);
    if (await localFile.exists()) {
      return _LocalResolvedExportReceiptFile(sourcePath);
    }

    return null;
  }

  String? _resolveSourcePath(Receipt receipt) {
    final processed = receipt.processedImagePath?.trim();
    if (processed != null && processed.isNotEmpty) {
      return processed;
    }

    final original = receipt.originalImagePath?.trim();
    if (original != null && original.isNotEmpty) {
      return original;
    }

    final legacy = receipt.imagePath?.trim();
    if (legacy != null && legacy.isNotEmpty) {
      return legacy;
    }

    return null;
  }
}

class SharePlusExportShareLauncher implements ExportShareLauncher {
  const SharePlusExportShareLauncher();

  @override
  Future<void> share({
    required String filePath,
    required String fileName,
    required BuildContext? context,
  }) async {
    final box = context?.findRenderObject() as RenderBox?;
    final origin = box != null && box.size.width > 0 && box.size.height > 0
        ? box.localToGlobal(Offset.zero) & box.size
        : const Rect.fromLTWH(0, 0, 1, 1);

    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(filePath, name: fileName)],
        subject: fileName,
        sharePositionOrigin: origin,
      ),
    );
  }
}

class _LocalResolvedExportReceiptFile extends ResolvedExportReceiptFile {
  _LocalResolvedExportReceiptFile(this.sourcePath);

  @override
  final String sourcePath;

  @override
  String? get contentType => null;

  @override
  Future<void> writeTo(File destination) async {
    final normalizedPath = sourcePath.startsWith('file://')
        ? Uri.parse(sourcePath).toFilePath()
        : sourcePath;
    final sourceFile = File(normalizedPath);
    if (!await sourceFile.exists()) {
      throw const FileSystemException('Local export source is missing.');
    }
    await sourceFile.copy(destination.path);
  }
}

class NetworkResolvedExportFile extends ResolvedExportReceiptFile {
  NetworkResolvedExportFile({
    required this.sourcePath,
    required this.client,
  });

  @override
  final String sourcePath;

  final http.Client client;
  String? _contentType;

  @override
  String? get contentType => _contentType;

  @override
  Future<void> writeTo(File destination) async {
    final response = await client.get(Uri.parse(sourcePath));
    if (response.statusCode != 200) {
      throw HttpException(
        'Failed to download export file: HTTP ${response.statusCode}',
        uri: Uri.parse(sourcePath),
      );
    }
    _contentType = response.headers['content-type'];
    await destination.writeAsBytes(response.bodyBytes, flush: true);
  }
}
