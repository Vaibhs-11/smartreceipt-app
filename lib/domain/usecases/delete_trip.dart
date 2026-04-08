import 'package:receiptnest/domain/repositories/trip_repository.dart';

class DeleteTripUseCase {
  const DeleteTripUseCase(this._repository);

  final TripRepository _repository;

  Future<void> call(String userId, String tripId) {
    return _repository.deleteTrip(userId, tripId);
  }
}
