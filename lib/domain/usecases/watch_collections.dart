import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';

class WatchCollectionsUseCase {
  const WatchCollectionsUseCase(this._repository);

  final CollectionRepository _repository;

  Stream<List<Collection>> call(String userId) {
    return _repository.watchCollections(userId);
  }
}
