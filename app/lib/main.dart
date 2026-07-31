import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/push.dart';
import 'core/session_storage.dart';
import 'core/theme.dart';
import 'data/auth_repository.dart';
import 'data/game_repository.dart';
import 'data/lobby_repository.dart';
import 'features/auth/auth_page.dart';
import 'features/lobby/lobby_page.dart';
import 'firebase_options.dart';

const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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

  @override
  void initState() {
    super.initState();
    _auth.changes.listen((state) {
      if (state.session != null && !_pushRegistered) {
        _pushRegistered = true;
        _setUpPush();
      }
      if (state.session == null) _pushRegistered = false;
      if (mounted) setState(() {});
    });

    if (_auth.isSignedIn) {
      _pushRegistered = true;
      _setUpPush();
    }
  }

  Future<void> _setUpPush() async {
    await _push.register();
    _pendingGameId = await _push.initialGameId();
    if (mounted) setState(() {});

    _push.openedGames.listen((gameId) {
      if (mounted) setState(() => _pendingGameId = gameId);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_auth.isSignedIn) return AuthPage(auth: _auth);

    return LobbyPage(
      key: ValueKey(_pendingGameId),
      auth: _auth,
      lobby: _lobby,
      games: _games,
      openGameId: _pendingGameId,
    );
  }
}
