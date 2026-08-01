import 'dart:async';

import 'package:onesignal_flutter/onesignal_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Push-Anmeldung für beide Welten.
///
/// OneSignal übernimmt die Geräte-Registrierung selbst (App-ID kommt aus
/// `web/index.html` bzw. dem nativen `OneSignal.initialize`-Aufruf in
/// `main.dart`). Was hier passiert, ist nur: um Erlaubnis fragen und den
/// Supabase-Nutzer per `login` mit der OneSignal-Subscription verknüpfen,
/// damit der Server über die `external_id` gezielt zustellen kann.
///
/// Auf iOS im Browser funktioniert Web-Push nur, wenn die Seite über
/// "Zum Home-Bildschirm" installiert wurde. Deshalb meldet [register] zurück,
/// ob es geklappt hat – die Oberfläche kann dann einen Hinweis zeigen, statt
/// dass Leute rätseln, warum nichts ankommt.
class PushService {
  PushService(this._client);
  final SupabaseClient _client;

  final _openedGames = StreamController<String>.broadcast();

  Future<bool> register() async {
    final user = _client.auth.currentUser;
    if (user == null) return false;

    final granted = await OneSignal.Notifications.requestPermission(true);
    if (!granted) return false;

    // Verknüpft dieses Gerät mit dem Supabase-Nutzer als OneSignal
    // external_id – darüber zielt der Server, ganz ohne eigene Token-Tabelle.
    await OneSignal.login(user.id);

    OneSignal.Notifications.addClickListener((event) {
      final gameId = event.notification.additionalData?['game_id'] as String?;
      if (gameId != null) _openedGames.add(gameId);
    });

    return true;
  }

  /// Partie-ID aus einer angetippten Meldung. Liefert auch den Fall ab, dass
  /// die App über den Tap erst gestartet wurde – OneSignal reicht diesen
  /// Klick nach, sobald der Listener registriert ist.
  Stream<String> get openedGames => _openedGames.stream;
}
