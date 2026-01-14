class AccountDeletionRequiresRecentLoginException implements Exception {
  const AccountDeletionRequiresRecentLoginException();
}

class AccountDeletionDataException implements Exception {
  const AccountDeletionDataException(this.message);

  final String message;

  @override
  String toString() => 'AccountDeletionDataException: $message';
}

class AccountDeletionAuthException implements Exception {
  const AccountDeletionAuthException({
    required this.code,
    this.message,
  });

  final String code;
  final String? message;

  @override
  String toString() =>
      'AccountDeletionAuthException(code: $code, message: $message)';
}

class AccountDeletionFunctionException implements Exception {
  const AccountDeletionFunctionException({
    required this.code,
    this.message,
  });

  final String code;
  final String? message;

  @override
  String toString() =>
      'AccountDeletionFunctionException(code: $code, message: $message)';
}
