import 'package:receiptnest/domain/entities/receipt.dart';
import 'package:receiptnest/domain/entities/trip.dart';

abstract class TripRepository {
  Future<void> createTrip(String userId, Trip trip);
  Future<void> updateTrip(String userId, Trip trip);
  /// Deletes the trip document only.
  ///
  /// Associated receipts are preserved and unlinked first by clearing their
  /// `tripId` field. Deleting a trip never deletes receipts.
  Future<void> deleteTrip(String userId, String tripId);
  Future<Trip?> getTrip(String userId, String tripId);
  Stream<Trip?> watchTrip(String userId, String tripId);
  Stream<List<Trip>> watchTrips(String userId);
  Future<List<Trip>> getTrips(String userId);
  Stream<List<Receipt>> watchReceiptsForTrip(String userId, String tripId);
  Future<List<Receipt>> getReceiptsForTrip(String userId, String tripId);
}
