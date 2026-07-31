import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push-Anmeldung für beide Welten.
///
/// Nativ holt FCM den Token vom Betriebssystem. Im Browser braucht es
/// zusätzlich den VAPID-Schlüssel aus der Firebase-Konsole und einen
/// Service Worker (web/firebase-messaging-sw.js).
///
/// Auf iOS im Browser funktioniert Web-Push nur, wenn die Seite über
/// "Zum Home-Bildschirm" installiert wurde. Deshalb meldet [register] zurück,
/// ob es geklappt hat – die Oberfläche kann dann einen Hinweis zeigen, statt
/// dass Leute rätseln, warum nichts ankommt.
class PushService {
  PushService(this._client);
  final SupabaseClient _client;

  static const _vapidKey = String.fromEnvironment('FCM_VAPID_KEY');

  Future<bool> register() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final messaging = FirebaseMessaging.instance;
    final settings = await messaging.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      return false;
    }

    final token = await messaging.getToken(
      vapidKey: kIsWeb && _vapidKey.isNotEmpty ? _vapidKey : null,
    );
    if (token == null) return false;

    await _save(user.id, token);

    // FCM erneuert Tokens gelegentlich von sich aus.
    messaging.onTokenRefresh.listen((fresh) => _save(user.id, fresh));
    return true;
  }

  Future<void> _save(String userId, String token) => _client.from('devices').upsert(
        {
          'user_id': userId,
          'fcm_token': token,
          'platform': kIsWeb
              ? 'web'
              : defaultTargetPlatform == TargetPlatform.iOS
                  ? 'ios'
                  : 'android',
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'fcm_token',
      );

  /// Partie-ID aus einer angetippten Meldung, falls die App darüber startete.
  Future<String?> initialGameId() async {
    final message = await FirebaseMessaging.instance.getInitialMessage();
    return message?.data['game_id'] as String?;
  }

  Stream<String> get openedGames => FirebaseMessaging.onMessageOpenedApp
      .map((m) => m.data['game_id'])
      .where((id) => id is String)
      .cast<String>();
}
