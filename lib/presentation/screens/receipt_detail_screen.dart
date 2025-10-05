import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:smartreceipt/domain/entities/receipt.dart';
import 'package:smartreceipt/presentation/providers/providers.dart';

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

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // --- Receipt file preview or link ---
                if (receipt.fileUrl != null && receipt.fileUrl!.isNotEmpty) ...[
                  _buildFilePreview(context, receipt.fileUrl!, receipt.storeName),
                  const SizedBox(height: 16),
                ] else if (receipt.imagePath != null &&
                    receipt.imagePath!.isNotEmpty &&
                    !receipt.imagePath!.startsWith('http')) ...[
                  GestureDetector(
                    onTap: () => _openFullImage(context, File(receipt.imagePath!)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        File(receipt.imagePath!),
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Text("Could not load local image"),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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

   /// --- Helper for network image, PDF or fallback link ---
  Widget _buildFilePreview(BuildContext context, String fileUrl, String storeName) {
    final lower = fileUrl.toLowerCase();
    final isNetwork = fileUrl.startsWith('http');
    final isImage = lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp');
    final isPdf = lower.endsWith('.pdf');

    // Extract readable filename for display
    final uri = Uri.parse(fileUrl);
    final rawName = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : fileUrl;
    final decodedName = Uri.decodeComponent(rawName);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isNetwork && isImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              fileUrl,
              height: 200,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Text("Could not load image preview"),
            ),
          )
        else
          const SizedBox.shrink(),

        const SizedBox(height: 8),

        // Always show the clickable file link
        _buildOpenFileLink(context, fileUrl, decodedName, storeName, isPdf),
      ],
    );
  }

  /// --- Builds a visible, clickable link card for any file type ---
  Widget _buildOpenFileLink(
      BuildContext context,
      String fileUrl,
      String fileName,
      String storeName,
      bool isPdf,
      ) {
    final icon = isPdf ? Icons.picture_as_pdf : Icons.link;

    return Card(
      color: Colors.grey[100],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        leading: Icon(icon, color: isPdf ? Colors.red : Colors.blue),
        title: Text(
          fileName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          storeName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.open_in_new),
        onTap: () async {
          final uri = Uri.parse(fileUrl);
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            ScaffoldMessenger.of(context).showSnackBar(
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

  /// Opens network image full screen
  void _openFullImageUrl(BuildContext context, String imageUrl) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _FullImageView(imageProvider: NetworkImage(imageUrl)),
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
