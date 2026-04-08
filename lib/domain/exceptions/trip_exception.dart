class DuplicateActiveTripException implements Exception {
  const DuplicateActiveTripException([
    this.message = 'You already have an active trip with this name',
  ]);

  final String message;

  @override
  String toString() => message;
}
