class TrialAlreadyUsedException implements Exception {
  const TrialAlreadyUsedException();

  @override
  String toString() => 'TrialAlreadyUsedException: trial has already been used.';
}
