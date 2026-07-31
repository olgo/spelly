import 'package:supabase_flutter/supabase_flutter.dart';

class PlayerEntry {
  const PlayerEntry({
    required this.id,
    required this.displayName,
    required this.openGames,
    required this.myTurnGames,
    required this.pendingInviteId,
    required this.inviteFromMe,
  });

  final String id;
  final String displayName;
  final int openGames;
  final int myTurnGames;

  /// Läuft gerade eine unbeantwortete Einladung zwischen euch?
  final String? pendingInviteId;
  final bool inviteFromMe;

  bool get hasPendingInvite => pendingInviteId != null;

  factory PlayerEntry.fromRow(Map<String, dynamic> row) => PlayerEntry(
        id: row['id'] as String,
        displayName: row['display_name'] as String,
        openGames: row['open_games'] as int? ?? 0,
        myTurnGames: row['my_turn_games'] as int? ?? 0,
        pendingInviteId: row['pending_invite'] as String?,
        inviteFromMe: row['invite_from_me'] as bool? ?? false,
      );
}

class GameEntry {
  const GameEntry({
    required this.id,
    required this.opponentName,
    required this.status,
    required this.myTurn,
    required this.myScore,
    required this.opponentScore,
    required this.invitedMe,
    required this.lastMoveAt,
  });

  final String id;
  final String opponentName;
  final String status;
  final bool myTurn;
  final int myScore;
  final int opponentScore;

  /// Eine Einladung, die noch auf meine Antwort wartet.
  final bool invitedMe;
  final DateTime lastMoveAt;

  bool get isInvitation => status == 'waiting';
}

class LobbyRepository {
  LobbyRepository(this._client);
  final SupabaseClient _client;

  String get _userId => _client.auth.currentUser!.id;

  Future<List<PlayerEntry>> players() async {
    final rows = await _client.rpc('list_players') as List<dynamic>;
    return rows
        .map((r) => PlayerEntry.fromRow((r as Map).cast<String, dynamic>()))
        .toList();
  }

  /// Alle Partien, in denen ich stecke – aktive, Einladungen und beendete.
  Future<List<GameEntry>> games() async {
    final rows = await _client
        .from('game_players')
        .select(
          'seat, score, games!inner(id, status, current_seat, last_move_at)',
        )
        .eq('player_id', _userId);

    final entries = <GameEntry>[];

    for (final row in rows) {
      final game = (row['games'] as Map).cast<String, dynamic>();
      final gameId = game['id'] as String;
      final mySeat = row['seat'] as int;

      // Gegnerdaten separat, weil PostgREST keinen Selbst-Join über dieselbe
      // Tabelle in einem Rutsch liefert.
      final other = await _client
          .from('game_players')
          .select('score, profiles(display_name)')
          .eq('game_id', gameId)
          .neq('player_id', _userId)
          .maybeSingle();

      entries.add(GameEntry(
        id: gameId,
        opponentName:
            (other?['profiles'] as Map?)?['display_name'] as String? ?? 'Gegner',
        status: game['status'] as String,
        myTurn: game['current_seat'] == mySeat,
        myScore: row['score'] as int,
        opponentScore: other?['score'] as int? ?? 0,
        invitedMe: game['status'] == 'waiting' && mySeat == 1,
        lastMoveAt: DateTime.parse(game['last_move_at'] as String),
      ));
    }

    entries.sort((a, b) {
      // Was auf mich wartet, zuerst.
      int rank(GameEntry e) => e.invitedMe
          ? 0
          : e.status == 'active' && e.myTurn
              ? 1
              : e.status == 'active'
                  ? 2
                  : 3;
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : b.lastMoveAt.compareTo(a.lastMoveAt);
    });

    return entries;
  }

  /// Herausfordern. Ergibt eine Partie im Status "waiting".
  Future<String?> challenge(String opponentId) async {
    final response = await _client.functions.invoke(
      'create-game',
      body: {'opponent_id': opponentId},
    );
    final data = (response.data as Map?)?.cast<String, dynamic>() ?? {};
    if (response.status >= 400 || data['error'] != null) {
      throw ChallengeFailed(data['error'] as String? ?? 'unknown_error');
    }
    return data['game_id'] as String?;
  }

  Future<String> respond(String gameId, {required bool accept}) async {
    final result = await _client.rpc(
      'respond_invitation',
      params: {'p_game_id': gameId, 'p_accept': accept},
    );
    return result as String;
  }

  /// Neue Version verfügbar? Ohne Store merkt das sonst niemand.
  Future<Map<String, dynamic>?> latestRelease(String platform) async {
    final row = await _client
        .from('app_release')
        .select()
        .eq('platform', platform)
        .maybeSingle();
    return row?.cast<String, dynamic>();
  }
}

class ChallengeFailed implements Exception {
  const ChallengeFailed(this.code);
  final String code;

  String get message => switch (code) {
        'invite_pending' =>
          'Zwischen euch liegt schon eine offene Einladung.',
        'same_player' => 'Gegen dich selbst geht nicht.',
        _ => 'Die Herausforderung ging nicht raus.',
      };
}
