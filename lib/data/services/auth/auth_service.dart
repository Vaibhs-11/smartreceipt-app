class AppUser {
  const AppUser({required this.uid, this.email});
  final String uid;
  final String? email;
}

abstract class AuthService {
  Stream<AppUser?> authStateChanges();
  Future<AppUser?> signInAnonymously();
  Future<void> signOut();
}

class AuthServiceStub implements AuthService {
  AppUser? _current;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _current;
  }

  @override
  Future<AppUser?> signInAnonymously() async {
    _current = const AppUser(uid: 'local-user');
    return _current;
  }

  @override
  Future<void> signOut() async {
    _current = null;
  }
}


