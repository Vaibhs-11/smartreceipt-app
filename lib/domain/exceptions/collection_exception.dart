class DuplicateActiveCollectionException implements Exception {
  const DuplicateActiveCollectionException([
    this.message = 'You already have an active collection with this name',
  ]);

  final String message;

  @override
  String toString() => message;
}
