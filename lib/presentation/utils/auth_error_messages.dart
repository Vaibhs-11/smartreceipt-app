import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

String friendlyAuthErrorMessage(
  Object error, {
  String fallback = 'Login failed. Please try again.',
}) {
  if (error is fb_auth.FirebaseAuthException) {
    switch (error.code) {
      case 'wrong-password':
      case 'invalid-credential':
        return 'The email or password you entered is incorrect.';
      case 'user-not-found':
        return 'No account found with this email address.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      default:
        return fallback;
    }
  }

  return fallback;
}
