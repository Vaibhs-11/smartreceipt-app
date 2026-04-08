import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';

class WatchTripUseCase {
  const WatchTripUseCase(this._repository);

  final TripRepository _repository;

  Stream<Trip?> call(String userId, String tripId) {
    return _repository.watchTrip(userId, tripId);
  }
}
