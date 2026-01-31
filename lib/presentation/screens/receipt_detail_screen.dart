import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';
import 'package:smartreceipt/presentation/utils/root_scaffold_messenger.dart';

class ReceiptDetailScreen extends ConsumerWidget {
  final String receiptId;
  const ReceiptDetailScreen({super.key, required this.receiptId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final receiptAsync = ref.watch(receiptDetailProvider(receiptId));

    return Scaffold(
      appBar: AppBar(title: const Text('Receipt Detail')),
      body: receiptAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('Error: $err')),
        data: (receipt) {
          if (receipt == null) {
            return const Center(child: Text('Receipt not found.'));
          }

          final currencyFormatter =
              NumberFormat.currency(symbol: receipt.currency);

          final displayImagePath = _resolveReceiptImagePath(receipt);
          final showProcessingBanner = displayImagePath != null &&
              receipt.processedImagePath == null &&
              receipt.imageProcessingStatus == 'pending';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // --- Receipt image or link section ---
                if (displayImagePath != null)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildImageOrFileSection(
                          context, displayImagePath, receipt.storeName),
                      if (showProcessingBanner) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: const [
                            SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            SizedBox(width: 8),
                            Text(
                              'Enhancing image...',
                              style: TextStyle(fontSize: 12),
                            )
                          ],
                        ),
                      ],
                    ],
                  ),

                const SizedBox(height: 16),

                // --- Store name & details ---
                Text(
                  receipt.storeName,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(DateFormat.yMMMMd().format(receipt.date)),
                const SizedBox(height: 8),
                Text(
                  currencyFormatter.format(receipt.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),

                // --- Itemized purchases ---
                if (receipt.items.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Items',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: receipt.items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = receipt.items[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(item.name),
                        trailing: Text(
                          currencyFormatter.format(item.price),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                      );
                    },
                  ),
                ],

                // --- Notes ---
                if (receipt.notes != null &&
                    receipt.notes!.trim().isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Text(
                    'Notes',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(receipt.notes!),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  String? _resolveReceiptImagePath(Receipt receipt) {
    final processed = receipt.processedImagePath;
    if (processed != null && processed.trim().isNotEmpty) return processed;

    final original = receipt.originalImagePath;
    if (original != null && original.trim().isNotEmpty) return original;

    final legacy = receipt.imagePath;
    if (legacy != null && legacy.trim().isNotEmpty) return legacy;
    return null;
  }

  /// --- Determines whether it's a network image, local file, or PDF ---
  Widget _buildImageOrFileSection(
      BuildContext context, String path, String storeName) {
    if (path.startsWith('http')) {
      return _buildRemoteImageOrFile(context, path, storeName, path);
    }

    final isLocalFile = path.startsWith('/') || path.startsWith('file://');
    if (isLocalFile) {
      return _buildLocalImage(context, path);
    }

    // Storage paths (e.g., receipts/{uid}/{id}/processed.jpg) must be
    // resolved into download URLs before rendering.
    return FutureBuilder<String>(
      future: FirebaseStorage.instance.ref(path).getDownloadURL(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey[200],
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        if (!snapshot.hasData || snapshot.hasError) {
          return const Text("Unable to load receipt image");
        }

        final downloadUrl = snapshot.data!;
        return _buildRemoteImageOrFile(context, downloadUrl, storeName, path);
      },
    );
  }

  Widget _buildRemoteImageOrFile(
      BuildContext context, String url, String storeName, String typeSource) {
    final lower = typeSource.toLowerCase();
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
    final isPdf = lower.endsWith('.pdf');

    if (isImage) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              url,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Text("Could not load image preview"),
            ),
          ),
          const SizedBox(height: 8),
          _buildOpenFileLink(context, url, storeName, isPdf),
        ],
      );
    }

    // Non-image (PDF etc.) → show clickable link card only
    return _buildOpenFileLink(context, url, storeName, isPdf);
  }

  Widget _buildLocalImage(BuildContext context, String path) {
    return GestureDetector(
      onTap: () => _openFullImage(context, File(path)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.file(
          File(path),
          height: 200,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Text("Could not load local image"),
        ),
      ),
    );
  }

  /// --- Builds a visible, clickable link card for any network file ---
  Widget _buildOpenFileLink(
      BuildContext context, String fileUrl, String storeName, bool isPdf) {
    final icon = isPdf ? Icons.picture_as_pdf : Icons.link;

    // Extract readable filename
    final uri = Uri.parse(fileUrl);
    final rawName =
        uri.pathSegments.isNotEmpty ? uri.pathSegments.last : fileUrl;
    final decodedName = Uri.decodeComponent(rawName);

    return Card(
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: isPdf ? Colors.red : Colors.blue),
        title: Text(
          decodedName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(storeName),
        trailing: const Icon(Icons.open_in_new),
        onTap: () async {
          final uri = Uri.parse(fileUrl);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            showRootSnackBar(
              const SnackBar(content: Text("Could not open link")),
            );
          }
        },
      ),
    );
  }

  /// Opens local image full screen
  void _openFullImage(BuildContext context, File imageFile) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullImageView(imageProvider: FileImage(imageFile)),
      ),
    );
  }
}

/// --- Full Image View Screen ---
class _FullImageView extends StatelessWidget {
  final ImageProvider imageProvider;
  const _FullImageView({required this.imageProvider});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      backgroundColor: Colors.black,
      body: Center(
        child: InteractiveViewer(
          panEnabled: true,
          minScale: 0.5,
          maxScale: 4.0,
          child: Image(image: imageProvider),
        ),
      ),
    );
  }
}
