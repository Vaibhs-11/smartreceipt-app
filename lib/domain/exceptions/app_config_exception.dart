class AppConfigUnavailableException implements Exception {
  const AppConfigUnavailableException(this.message);

  final String message;

  @override
  String toString() => 'AppConfigUnavailableException: $message';
}
