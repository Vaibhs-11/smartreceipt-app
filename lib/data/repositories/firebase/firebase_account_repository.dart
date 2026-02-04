import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:flutter/foundation.dart';
import 'package:receiptnest/domain/exceptions/account_deletion_exception.dart';
import 'package:receiptnest/domain/repositories/account_repository.dart';

class FirebaseAccountRepository implements AccountRepository {
  FirebaseAccountRepository({
    fb_auth.FirebaseAuth? authInstance,
    FirebaseFunctions? functionsInstance,
  })  : _auth = authInstance ?? fb_auth.FirebaseAuth.instance,
        _functions = functionsInstance ?? FirebaseFunctions.instance;

  final fb_auth.FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  @override
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) {
      debugPrint('Skipping deleteAccount: user not logged in.');
      return;
    }

    try {
      final callable = _functions.httpsCallable('deleteAccount');
      final result = await callable();
      final data = result.data;
      if (data is! Map || data['success'] != true) {
        debugPrint(
          'Account deletion callable returned unexpected response: $data',
        );
        throw const AccountDeletionFunctionException(
          code: 'unexpected-response',
          message: 'deleteAccount callable did not return success.',
        );
      }
    } on FirebaseFunctionsException catch (e, stackTrace) {
      debugPrint(
        'Account deletion callable failed '
        '(code: ${e.code}, message: ${e.message})',
      );
      debugPrintStack(stackTrace: stackTrace);
      throw AccountDeletionFunctionException(code: e.code, message: e.message);
    } catch (e, stackTrace) {
      debugPrint('Account deletion callable failed: $e');
      debugPrintStack(stackTrace: stackTrace);
      throw AccountDeletionFunctionException(
        code: 'unknown',
        message: e.toString(),
      );
    }

    await _auth.signOut();
  }
}
