import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/auth_link.dart';
import 'core/onesignal_bridge.dart';
import 'core/push.dart';
import 'core/session_storage.dart';
import 'core/theme.dart';
import 'data/auth_repository.dart';
import 'data/game_repository.dart';
import 'data/lobby_repository.dart';
import 'features/auth/auth_page.dart';
import 'features/auth/new_password_page.dart';
import 'features/lobby/lobby_page.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

// Öffentlich wie die restliche Web-SDK-Konfiguration in web/index.html –
// der Schutz kommt aus den Supabase-Policies, nicht aus Geheimhaltung.
const oneSignalAppId = 'cec97100-f4a4-4d06-929b-80a2226fd8e4';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Im Web ein Leerlauf: Dort richtet `web/index.html` das JS-SDK ein, noch
  // bevor Flutter startet.
  OneSignalApi.initialize(oneSignalAppId);

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
    authOptions: FlutterAuthClientOptions(
      // Sitzung im Keychain bzw. Keystore, im Browser im Standardspeicher.
      localStorage: sessionStorage(),
      // Der Klick in der Bestätigungsmail landet hier wieder.
      authFlowType: AuthFlowType.pkce,
    ),
  );

  runApp(const SpellyApp());
}

class SpellyApp extends StatelessWidget {
  const SpellyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Spelly',
      theme: buildTheme(),
      debugShowCheckedModeBanner: false,
      home: const AuthGate(),
    );
  }
}

/// Entscheidet zwischen Anmeldung und Lobby und hält beides über die
/// Auth-Ereignisse aktuell. Weil die Sitzung gespeichert ist, sehen
/// wiederkehrende Spieler:innen den Anmeldebildschirm gar nicht erst.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final _client = Supabase.instance.client;
  late final _auth = AuthRepository(_client);
  late final _lobby = LobbyRepository(_client);
  late final _games = GameRepository(_client);
  late final _push = PushService(_client);

  String? _pendingGameId;
  bool _pushRegistered = false;

  /// Die Sitzung stammt aus einer Wiederherstellungsmail. Dann muss vor allem
  /// anderen ein neues Passwort gesetzt werden – sonst wäre der Link ein
  /// Einmal-Zugang gewesen und das vergessene Passwort stünde weiterhin.
  bool _recovering = false;

  @override
  void initState() {
    super.initState();
    _auth.changes.listen((state) {
      // Kommt zuverlässig an, auch wenn der Link die App überhaupt erst
      // gestartet hat: Der Ereignisstrom von gotrue ist ein BehaviorSubject
      // und reicht das letzte Ereignis an später hinzukommende Zuhörer nach.
      if (state.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      if (state.session != null && !_pushRegistered) {
        _pushRegistered = true;
        _setUpPush();
      }
      if (state.session == null) {
        _pushRegistered = false;
        _recovering = false;
      }
      if (mounted) setState(() {});
    },
        // Ein gescheitertes Einlösen eines Mail-Links kommt als Fehler auf
        // diesem Strom an. Ohne Handler wäre das ein unbehandelter Fehler in
        // der Ereignisschleife; die Erklärung für die Person am Bildschirm
        // liefert stattdessen `_linkProblem`.
        onError: (Object error) => debugPrint('auth state error: $error'));

    if (_auth.isSignedIn) {
      _pushRegistered = true;
      _setUpPush();
    }
  }

  Future<void> _setUpPush() async {
    // Nur verknüpfen, nicht fragen: Nach der Erlaubnis fragt der Knopf in der
    // Lobby, damit der Systemdialog aus einer frischen Nutzergeste kommt.
    await _push.link();
    _push.openedGames.listen((gameId) {
      if (mounted) setState(() => _pendingGameId = gameId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isSignedIn) {
      return AuthPage(auth: _auth, initialError: linkProblem(Uri.base));
    }

    if (_recovering) {
      return NewPasswordPage(
        auth: _auth,
        onDone: () => setState(() => _recovering = false),
      );
    }

    return LobbyPage(
      key: ValueKey(_pendingGameId),
      auth: _auth,
      lobby: _lobby,
      games: _games,
      push: _push,
      openGameId: _pendingGameId,
    );
  }
}
