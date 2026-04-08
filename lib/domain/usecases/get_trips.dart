import 'package:receiptnest/domain/entities/trip.dart';
import 'package:receiptnest/domain/repositories/trip_repository.dart';

class GetTripsUseCase {
  const GetTripsUseCase(this._repository);

  final TripRepository _repository;

  Future<List<Trip>> call(String userId) {
    return _repository.getTrips(userId);
  }
}
