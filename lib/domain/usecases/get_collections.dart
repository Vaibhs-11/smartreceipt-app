import 'package:receiptnest/domain/entities/collection.dart';
import 'package:receiptnest/domain/repositories/collection_repository.dart';

class GetCollectionsUseCase {
  const GetCollectionsUseCase(this._repository);

  final CollectionRepository _repository;

  Future<List<Collection>> call(String userId) {
    return _repository.getCollections(userId);
  }
}
