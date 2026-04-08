import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';

class WatchTripsUseCase {
  const WatchTripsUseCase(this._repository);

  final TripRepository _repository;

  Stream<List<Trip>> call(String userId) {
    return _repository.watchTrips(userId);
  }
}
