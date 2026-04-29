import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';

class GetCollectionUseCase {
  const GetCollectionUseCase(this._repository);

  final CollectionRepository _repository;

  Future<Collection?> call(String userId, String collectionId) {
    return _repository.getCollection(userId, collectionId);
  }
}
