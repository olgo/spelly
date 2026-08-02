import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Grund, warum eine Anmeldung nicht geklappt hat – in Codes, damit die
/// Oberfläche die Texte bestimmt.
enum AuthProblem {
  invalidCredentials,
  emailNotConfirmed,
  emailTaken,
  weakPassword,
  invalidEmail,
  rateLimited,
  unknown,
}

class AuthFailure implements Exception {
  const AuthFailure(this.problem, [this.raw]);
  final AuthProblem problem;
  final String? raw;
}

class AuthRepository {
  AuthRepository(this._client);
  final SupabaseClient _client;

  Session? get session => _client.auth.currentSession;
  User? get user => _client.auth.currentUser;
  bool get isSignedIn => session != null;

  /// Feuert bei Anmeldung, Abmeldung und stiller Erneuerung des Tokens.
  Stream<AuthState> get changes => _client.auth.onAuthStateChange;

  /// Registrierung. Die Bestätigungsmail geht raus, angemeldet ist man erst
  /// nach dem Klick darin – deshalb gibt es hier keine Session zurück.
  Future<void> signUp({
    required String email,
    required String password,
    required String displayName,
  }) async {
    try {
      await _client.auth.signUp(
        email: email.trim(),
        password: password,
        // Der Trigger handle_new_user liest den Namen hier heraus.
        data: {'display_name': displayName.trim(), 'locale': 'de'},
        emailRedirectTo: _redirectTo,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_classify(e), e.message);
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_classify(e), e.message);
    }
  }

  Future<void> resendConfirmation(String email) async {
    try {
      await _client.auth.resend(
        type: OtpType.signup,
        email: email.trim(),
        emailRedirectTo: _redirectTo,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_classify(e), e.message);
    }
  }

  Future<void> sendPasswordReset(String email) async {
    try {
      await _client.auth.resetPasswordForEmail(
        email.trim(),
        redirectTo: _redirectTo,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_classify(e), e.message);
    }
  }

  Future<void> signOut() async {
    // Beim Abmelden die OneSignal-Subscription vom Nutzer lösen, sonst
    // bekommt das Gerät weiter Meldungen für ein Konto, das hier niemand
    // mehr benutzt.
    await OneSignal.logout();
    await _client.auth.signOut();
  }

  Future<void> rename(String displayName) =>
      _client.from('profiles').update({'display_name': displayName.trim()}).eq(
          'id', user!.id);

  /// Nach dem Klick in der Bestätigungsmail landet man wieder in der App.
  /// Die Web-Variante nutzt die Adresse der Seite, die App ihr URL-Schema.
  static const _redirectTo = String.fromEnvironment(
    'AUTH_REDIRECT',
    defaultValue: 'spelly://login-callback',
  );

  static AuthProblem _classify(AuthException e) {
    final message = e.message.toLowerCase();
    if (message.contains('email not confirmed')) {
      return AuthProblem.emailNotConfirmed;
    }
    if (message.contains('invalid login')) return AuthProblem.invalidCredentials;
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return AuthProblem.emailTaken;
    }
    if (message.contains('password') && message.contains('least')) {
      return AuthProblem.weakPassword;
    }
    if (message.contains('invalid email') || message.contains('valid email')) {
      return AuthProblem.invalidEmail;
    }
    if (message.contains('rate limit') || message.contains('too many')) {
      return AuthProblem.rateLimited;
    }
    return AuthProblem.unknown;
  }
}
