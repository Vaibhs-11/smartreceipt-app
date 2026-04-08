import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';

class CreateTripUseCase {
  const CreateTripUseCase(this._repository);

  final TripRepository _repository;

  Future<void> call(String userId, Trip trip) {
    return _repository.createTrip(userId, trip);
  }
}
