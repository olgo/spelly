import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'onesignal_bridge.dart';

/// Push-Anmeldung für beide Welten.
///
/// OneSignal übernimmt die Geräte-Registrierung selbst (App-ID kommt aus
/// `web/index.html` bzw. dem nativen `initialize`-Aufruf in `main.dart`). Was
/// hier passiert, ist nur: den Supabase-Nutzer per `login` mit der
/// OneSignal-Anmeldung verknüpfen, damit der Server über die `external_id`
/// gezielt zustellen kann – und, getrennt davon, um Erlaubnis fragen.
///
/// Getrennt, weil beides zu verschiedenen Zeitpunkten gehört: Die Verknüpfung
/// darf still gleich nach dem Anmelden laufen, der Systemdialog dagegen
/// braucht auf iOS eine frische Nutzergeste – er kommt deshalb erst auf
/// Tippen in der Lobby.
class PushService {
  PushService(this._client);
  final SupabaseClient _client;

  final _openedGames = StreamController<String>.broadcast();
  bool _listening = false;

  /// Ob dieser Browser Push überhaupt kann. Auf dem iPhone heisst `false`:
  /// noch im Safari-Tab statt in der Home-Bildschirm-App.
  bool get isSupported => OneSignalApi.isSupported;

  bool get hasPermission => OneSignalApi.hasPermission;

  /// Ob dieses Gerät bei OneSignal wirklich als Empfänger eingetragen ist –
  /// die Frage, die für „bekommt man Meldungen" eigentlich zählt, siehe
  /// OneSignalApi.isSubscribed.
  Future<bool> isSubscribed() => OneSignalApi.isSubscribed();

  /// Verknüpft dieses Gerät mit dem Supabase-Nutzer als OneSignal
  /// `external_id` – darüber zielt der Server, ganz ohne eigene Token-Tabelle.
  ///
  /// Läuft gleich nach der Anmeldung, auch ohne erteilte Erlaubnis: Die
  /// Kennung darf früh stehen, der Push-Schlüssel hängt sich später von selbst
  /// daran, sobald jemand zustimmt.
  Future<void> link() async {
    final user = _client.auth.currentUser;
    if (user == null) return;

    if (!_listening) {
      _listening = true;
      OneSignalApi.onClick((data) {
        final gameId = data?['game_id'] as String?;
        if (gameId != null) _openedGames.add(gameId);
      });
    }

    try {
      await OneSignalApi.login(user.id);
    } catch (error) {
      // Kein Grund, die App aufzuhalten – dann kommen eben keine Meldungen an.
      debugPrint('OneSignal login failed: $error');
    }
  }

  /// Fragt nach der Erlaubnis. Gehört an einen Knopf: Der Systemdialog
  /// erscheint nur, solange die Nutzergeste frisch ist.
  ///
  /// Meldet `false` auch dann, wenn schon einmal abgelehnt wurde – das System
  /// zeigt den Dialog dann gar nicht mehr, und es hilft nur noch der Weg über
  /// die Einstellungen.
  Future<bool> enable() async {
    final user = _client.auth.currentUser;
    if (user == null || !OneSignalApi.isSupported) return false;

    try {
      final granted = await OneSignalApi.requestPermission();
      if (!granted) return false;
      // Noch einmal: Beim ersten Mal ist die Anmeldung womöglich erst durch
      // die erteilte Erlaubnis entstanden.
      await OneSignalApi.login(user.id);
      return true;
    } catch (error) {
      debugPrint('OneSignal permission request failed: $error');
      return false;
    }
  }

  /// Partie-ID aus einer angetippten Meldung. Liefert auch den Fall ab, dass
  /// die App über den Tap erst gestartet wurde – OneSignal reicht diesen
  /// Klick nach, sobald der Listener registriert ist.
  Stream<String> get openedGames => _openedGames.stream;
}
