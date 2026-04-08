import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';

class GetTripUseCase {
  const GetTripUseCase(this._repository);

  final TripRepository _repository;

  Future<Trip?> call(String userId, String tripId) {
    return _repository.getTrip(userId, tripId);
  }
}
