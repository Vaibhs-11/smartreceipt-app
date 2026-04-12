import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';

class WatchCollectionUseCase {
  const WatchCollectionUseCase(this._repository);

  final CollectionRepository _repository;

  Stream<Collection?> call(String userId, String collectionId) {
    return _repository.watchCollection(userId, collectionId);
  }
}
