import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smartreceipt/data/services/auth/auth_service.dart';

// 1. State class for authentication
class AuthState {
  const AuthState({this.isLoading = false, this.error});
  final bool isLoading;
  final Object? error;

  bool get hasError => error != null;

  AuthState copyWith({bool? isLoading, Object? error}) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      // When updating, we either pass a new error or clear the existing one.
      // Passing null to `error` will clear it.
      error: error,
    );
  }
}

// 2. Controller to manage the state
class AuthController extends StateNotifier<AuthState> {
  AuthController(this._authService) : super(const AuthState());

  final AuthService _authService;

  // Helper to run an auth action and manage loading/error states
  Future<void> _run(Future<void> Function() action) async {
    // Set loading state and clear previous errors
    state = state.copyWith(isLoading: true, error: null);
    try {
      await action();
    } catch (e) {
      state = state.copyWith(error: e);
      rethrow; // Rethrow to be caught in the UI for snackbars, etc.
    } finally {
      // Always turn off loading state
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> signInWithEmailPassword(String email, String password) async {
    await _run(() => _authService.signInWithEmailAndPassword(email, password));
  }

  Future<void> signUpWithEmailPassword(String email, String password) async {
    await _run(() => _authService.createUserWithEmailAndPassword(email, password));
  }

  Future<void> signOut() async {
    await _run(_authService.signOut);
  }
}