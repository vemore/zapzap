import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:zapzap/services/google_sign_in_service.dart';

/// Google replaced: [signIn] hands over [nextToken], or fails with
/// [nextFailure], or does nothing (the user closed the dialog) when both are
/// `null`.
class FakeGoogleSignIn implements GoogleSignInService {
  final _tokens = StreamController<String>.broadcast();
  String? nextToken = 'google-id-token';
  Object? nextFailure;

  /// Thrown by [signIn] itself (a failure the token stream does not carry).
  Object? signInThrows;
  int signIns = 0;

  /// What [ready] answers; ready at once by default. A future that never
  /// completes stands for Google's script blocked.
  Future<void> Function() onReady = () async {};

  /// Thrown by [signOut].
  Object? signOutThrows;

  /// Awaited by [signOut]; a future that never completes stands for Google
  /// not answering.
  Future<void> Function()? onSignOut;
  int signOuts = 0;

  /// Google's own button, as on the web; `null`: the app draws one.
  Widget Function()? webButton;
  int platformButtonCalls = 0;

  /// A token handed over by Google's own button, bypassing [signIn].
  void emit(String token) => _tokens.add(token);

  @override
  bool get enabled => true;

  @override
  Future<void> ready() => onReady();

  @override
  Stream<String> get idTokens => _tokens.stream;

  @override
  Widget? platformButton(BuildContext context) {
    platformButtonCalls++;
    return webButton?.call();
  }

  @override
  Future<void> signIn() async {
    signIns++;
    if (signInThrows != null) throw signInThrows!;
    if (nextFailure != null) {
      _tokens.addError(nextFailure!);
    } else if (nextToken != null) {
      _tokens.add(nextToken!);
    }
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    if (signOutThrows != null) throw signOutThrows!;
    await onSignOut?.call();
  }
}
