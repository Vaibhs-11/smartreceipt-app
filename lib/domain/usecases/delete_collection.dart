import 'package:receiptnest/domain/repositories/collection_repository.dart';

class DeleteCollectionUseCase {
  const DeleteCollectionUseCase(this._repository);

  final CollectionRepository _repository;

  Future<void> call(String userId, String collectionId) {
    return _repository.deleteCollection(userId, collectionId);
  }
}
