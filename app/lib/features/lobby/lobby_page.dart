import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth_repository.dart';
import '../../data/game_repository.dart';
import '../../data/lobby_repository.dart';
import '../game/game_page.dart';

class LobbyPage extends StatefulWidget {
  const LobbyPage({
    super.key,
    required this.auth,
    required this.lobby,
    required this.games,
    this.openGameId,
  });

  final AuthRepository auth;
  final LobbyRepository lobby;
  final GameRepository games;

  /// Kommt aus einer angetippten Benachrichtigung.
  final String? openGameId;

  @override
  State<LobbyPage> createState() => _LobbyPageState();
}

class _LobbyPageState extends State<LobbyPage> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  List<GameEntry> _games = const [];
  List<PlayerEntry> _players = const [];
  bool _loading = true;
  String? _message;

  @override
  void initState() {
    super.initState();
    _refresh();
    if (widget.openGameId != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openGame(widget.openGameId!),
      );
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final games = await widget.lobby.games();
    final players = await widget.lobby.players();
    if (!mounted) return;
    setState(() {
      _games = games;
      _players = players;
      _loading = false;
    });
  }

  void _openGame(String id) {
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => GamePage(repository: widget.games, gameId: id),
        ))
        .then((_) => _refresh());
  }

  Future<void> _challenge(PlayerEntry player) async {
    try {
      await widget.lobby.challenge(player.id);
      setState(() => _message = '${player.displayName} ist herausgefordert.');
    } on ChallengeFailed catch (e) {
      setState(() => _message = e.message);
    } catch (_) {
      setState(() => _message = 'Das hat nicht geklappt. Versuch es nochmal.');
    }
    await _refresh();
  }

  Future<void> _respond(GameEntry game, {required bool accept}) async {
    try {
      final status = await widget.lobby.respond(game.id, accept: accept);
      if (!mounted) return;
      if (accept && status == 'active') {
        _openGame(game.id);
        return;
      }
    } catch (_) {
      setState(() => _message = 'Das hat nicht geklappt. Versuch es nochmal.');
    }
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.graphite,
        title: const Text('Spelly'),
        actions: [
          IconButton(
            tooltip: 'Abmelden',
            icon: const Icon(Icons.logout, size: 20),
            onPressed: () => widget.auth.signOut(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Palette.signal,
          labelColor: Palette.text,
          unselectedLabelColor: Palette.textDim,
          tabs: const [
            Tab(text: 'Partien'),
            Tab(text: 'Spieler:innen'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_message != null)
            Container(
              width: double.infinity,
              color: Palette.boardInk,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _message!,
                style: const TextStyle(color: Palette.signal, fontSize: 13),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabs,
                    children: [
                      _GamesTab(
                        games: _games,
                        onOpen: _openGame,
                        onRespond: _respond,
                        onRefresh: _refresh,
                      ),
                      _PlayersTab(
                        players: _players,
                        onChallenge: _challenge,
                        onRefresh: _refresh,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _GamesTab extends StatelessWidget {
  const _GamesTab({
    required this.games,
    required this.onOpen,
    required this.onRespond,
    required this.onRefresh,
  });

  final List<GameEntry> games;
  final void Function(String) onOpen;
  final Future<void> Function(GameEntry, {required bool accept}) onRespond;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (games.isEmpty) {
      return _Empty(
        title: 'Noch keine Partie',
        body: 'Wechsle zu Spieler:innen und fordere jemanden heraus.',
        onRefresh: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: games.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Palette.hairline),
        itemBuilder: (context, i) {
          final game = games[i];

          if (game.invitedMe) {
            return _InvitationRow(game: game, onRespond: onRespond);
          }

          final subtitle = switch (game.status) {
            'waiting' => 'Wartet auf Antwort',
            'active' => game.myTurn ? 'Du bist am Zug' : 'Gegner ist am Zug',
            _ => 'Beendet',
          };

          return ListTile(
            onTap: game.status == 'waiting' ? null : () => onOpen(game.id),
            title: Text(game.opponentName,
                style: const TextStyle(color: Palette.text)),
            subtitle: Text(subtitle,
                style: TextStyle(
                  color: game.myTurn && game.status == 'active'
                      ? Palette.signal
                      : Palette.textDim,
                  fontSize: 12.5,
                )),
            trailing: Text(
              '${game.myScore} : ${game.opponentScore}',
              style: const TextStyle(
                color: Palette.text,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _InvitationRow extends StatelessWidget {
  const _InvitationRow({required this.game, required this.onRespond});

  final GameEntry game;
  final Future<void> Function(GameEntry, {required bool accept}) onRespond;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Palette.boardInk,
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${game.opponentName} fordert dich heraus',
                    style: const TextStyle(
                        color: Palette.text, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('Nimm an, dann geht es sofort los.',
                    style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
          TextButton(
            onPressed: () => onRespond(game, accept: false),
            child: const Text('Ablehnen'),
          ),
          const SizedBox(width: 4),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Palette.signal,
              foregroundColor: Palette.boneInk,
            ),
            onPressed: () => onRespond(game, accept: true),
            child: const Text('Annehmen'),
          ),
        ],
      ),
    );
  }
}

class _PlayersTab extends StatelessWidget {
  const _PlayersTab({
    required this.players,
    required this.onChallenge,
    required this.onRefresh,
  });

  final List<PlayerEntry> players;
  final Future<void> Function(PlayerEntry) onChallenge;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (players.isEmpty) {
      return _Empty(
        title: 'Noch niemand da',
        body: 'Sobald sich jemand anmeldet, steht er hier.',
        onRefresh: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 8),
        itemCount: players.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 1, color: Palette.hairline),
        itemBuilder: (context, i) {
          final player = players[i];

          final subtitle = player.hasPendingInvite
              ? (player.inviteFromMe
                  ? 'Deine Einladung läuft'
                  : 'Wartet auf deine Antwort')
              : player.openGames == 0
                  ? 'Keine laufende Partie'
                  : '${player.openGames} laufende '
                      '${player.openGames == 1 ? "Partie" : "Partien"}';

          return ListTile(
            title: Text(player.displayName,
                style: const TextStyle(color: Palette.text)),
            subtitle: Text(subtitle,
                style: const TextStyle(color: Palette.textDim, fontSize: 12.5)),
            trailing: player.hasPendingInvite
                ? const Icon(Icons.hourglass_empty,
                    size: 18, color: Palette.textDim)
                : OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Palette.signal,
                      side: const BorderSide(color: Palette.hairline),
                    ),
                    onPressed: () => onChallenge(player),
                    child: const Text('Herausfordern'),
                  ),
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({
    required this.title,
    required this.body,
    required this.onRefresh,
  });

  final String title;
  final String body;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(body, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
