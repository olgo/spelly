import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/onesignal_bridge.dart';

/// Grund, warum eine Anmeldung nicht geklappt hat – in Codes, damit die
/// Oberfläche die Texte bestimmt.
enum AuthProblem {
  invalidCredentials,
  emailNotConfirmed,
  emailTaken,
  weakPassword,
  samePassword,
  invalidCode,
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

  /// Löst den sechsstelligen Code aus der Wiederherstellungsmail ein.
  ///
  /// Der Weg über einen Link ist auf dem iPhone eine Sackgasse: iOS öffnet
  /// Links immer im Standardbrowser, nie in einer Home-Bildschirm-App. Der
  /// PKCE-Prüfschlüssel entsteht aber dort, wo die Mail angefordert wurde –
  /// und die drei Speicher (App, Safari, Standardbrowser) sind vollständig
  /// getrennt. Ein Code kennt dieses Problem nicht: Er wird da eingetippt, wo
  /// man ohnehin schon steht.
  ///
  /// Löst dasselbe `passwordRecovery`-Ereignis aus wie ein eingelöster Link
  /// (`gotrue_client.dart:632`) – die Weiche im AuthGate bleibt also dieselbe.
  Future<void> verifyRecoveryCode({
    required String email,
    required String code,
  }) async {
    try {
      await _client.auth.verifyOTP(
        email: email.trim(),
        token: code.trim(),
        type: OtpType.recovery,
      );
    } on AuthException catch (e) {
      throw AuthFailure(_classify(e), e.message);
    }
  }

  /// Setzt ein neues Passwort für die laufende Sitzung.
  ///
  /// Der eigentliche Abschluss von „Passwort vergessen": Der Klick in der Mail
  /// meldet zwar an, ändert aber nichts. Ohne diesen Schritt bliebe das alte,
  /// vergessene Passwort stehen – und beim nächsten Start stünde man wieder
  /// vor derselben Maske.
  Future<void> updatePassword(String password) async {
    try {
      await _client.auth.updateUser(UserAttributes(password: password));
    } on AuthException catch (e) {
      throw AuthFailure(_classify(e), e.message);
    }
  }

  Future<void> signOut() async {
    // Beim Abmelden die OneSignal-Subscription vom Nutzer lösen, sonst
    // bekommt das Gerät weiter Meldungen für ein Konto, das hier niemand
    // mehr benutzt. Best effort: darf das eigentliche Abmelden nicht
    // blockieren, falls OneSignal (noch) nicht erreichbar ist.
    try {
      await OneSignalApi.logout().timeout(const Duration(seconds: 3));
    } catch (_) {}
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
    // Falscher wie abgelaufener Code kommen mit demselben Satz zurück – das
    // ist Absicht, sonst liesse sich raten, welche Codes es gibt.
    if (message.contains('token has expired') ||
        message.contains('invalid or has expired')) {
      return AuthProblem.invalidCode;
    }
    if (message.contains('invalid login')) return AuthProblem.invalidCredentials;
    if (message.contains('already registered') ||
        message.contains('already been registered')) {
      return AuthProblem.emailTaken;
    }
    // Kommt nur beim Zurücksetzen vor: Supabase lehnt ab, wenn das neue
    // Passwort dem alten gleicht.
    if (message.contains('should be different')) {
      return AuthProblem.samePassword;
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
