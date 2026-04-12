import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';

class UpdateCollectionUseCase {
  const UpdateCollectionUseCase(this._repository);

  final CollectionRepository _repository;

  Future<void> call(String userId, Collection collection) {
    return _repository.updateCollection(userId, collection);
  }
}
