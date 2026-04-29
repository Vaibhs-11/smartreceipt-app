import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/entities/collection.dart';

abstract class CollectionRepository {
  Future<void> createCollection(String userId, Collection collection);
  Future<void> updateCollection(String userId, Collection collection);

  /// Deletes the collection document only.
  ///
  /// Associated receipts are preserved and unlinked first.
  /// Deleting a collection never deletes receipts.
  Future<void> deleteCollection(String userId, String collectionId);
  Future<Collection?> getCollection(String userId, String collectionId);
  Stream<Collection?> watchCollection(String userId, String collectionId);
  Stream<List<Collection>> watchCollections(String userId);
  Future<List<Collection>> getCollections(String userId);
  Stream<List<Receipt>> watchReceiptsForCollection(
    String userId,
    String collectionId,
  );
  Future<List<Receipt>> getReceiptsForCollection(
    String userId,
    String collectionId,
  );
}
