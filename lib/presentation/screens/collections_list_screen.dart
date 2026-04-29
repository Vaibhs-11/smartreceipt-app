import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:receiptnest/core/theme/app_colors.dart';
import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/presentation/providers/providers.dart';
import 'package:receiptnest/presentation/screens/collection_detail_screen.dart';
import 'package:receiptnest/presentation/screens/create_collection_screen.dart';

class CollectionsListScreen extends ConsumerWidget {
  const CollectionsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collectionsAsync = ref.watch(collectionsStreamProvider);
    final hasAccess = ref.watch(premiumCollectionAccessProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Trips & Events',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: AppColors.primaryNavy,
          ),
        ),
      ),
      body: SafeArea(
        child: !hasAccess
            ? const _CollectionsLockedView()
            : collectionsAsync.when(
                data: (collections) {
                  if (collections.isEmpty) {
                    return _CollectionsEmptyState(
                      onCreate: () => _openCreateCollection(context),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async {
                      ref.refresh(collectionsStreamProvider);
                      await ref.read(collectionsStreamProvider.future);
                    },
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                      itemCount: collections.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final collection = collections[index];
                        return _CollectionCard(
                          collection: collection,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => CollectionDetailScreen(
                                  collectionId: collection.id,
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) =>
                    Center(child: Text('Failed to load collections: $error')),
              ),
      ),
      floatingActionButton: hasAccess
          ? FloatingActionButton.extended(
              onPressed: () => _openCreateCollection(context),
              icon: const Icon(Icons.add),
              label: const Text('Create Trip or Event'),
            )
          : null,
    );
  }

  void _openCreateCollection(BuildContext context) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => const CreateCollectionScreen(),
      ),
    );
  }
}

class _CollectionCard extends StatelessWidget {
  const _CollectionCard({
    required this.collection,
    required this.onTap,
  });

  final Collection collection;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dateRange = _formatCollectionDateRange(collection);

    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        onTap: onTap,
        leading: const Icon(
          Icons.folder_copy_outlined,
          color: AppColors.primaryNavy,
        ),
        title: Text(
          collection.name,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 4),
            Text(
              collection.type == CollectionType.work ? 'Work' : 'Personal',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (dateRange != null) ...[
              const SizedBox(height: 4),
              Text(
                dateRange,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _CollectionsEmptyState extends StatelessWidget {
  const _CollectionsEmptyState({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'No trips or events yet',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.primaryNavy,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Create your first trip or event to organise related receipts in one place.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create Trip or Event'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CollectionsLockedView extends StatelessWidget {
  const _CollectionsLockedView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.workspace_premium_outlined,
                  size: 36,
                  color: AppColors.primaryNavy,
                ),
                SizedBox(height: 12),
                Text(
                  'Trips & Events are available on an active trial or subscription.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primaryNavy,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String? _formatCollectionDateRange(Collection collection) {
  if (collection.startDate == null && collection.endDate == null) {
    return null;
  }

  final formatter = DateFormat.yMMMd();
  final startText = collection.startDate == null
      ? 'Any start'
      : formatter.format(collection.startDate!);
  final endText = collection.endDate == null
      ? 'Any end'
      : formatter.format(collection.endDate!);
  return '$startText - $endText';
}
