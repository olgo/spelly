import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/rules.dart';

class GameSnapshot {
  const GameSnapshot({
    required this.id,
    required this.board,
    required this.rack,
    required this.mySeat,
    required this.currentSeat,
    required this.myScore,
    required this.opponentScore,
    required this.opponentName,
    required this.tilesLeft,
    required this.dictVersion,
    required this.status,
  });

  final String id;
  final List<Tile?> board;
  final List<String> rack;
  final int mySeat;
  final int currentSeat;
  final int myScore;
  final int opponentScore;
  final String opponentName;
  final int tilesLeft;
  final String dictVersion;
  final String status;

  bool get isMyTurn => status == 'active' && mySeat == currentSeat;
}

/// Der Server hat den Zug abgelehnt. [code] ist einer der Regelcodes aus
/// rules.ts, etwa invalid_word oder stale_turn.
class MoveRejected implements Exception {
  const MoveRejected(this.code, [this.detail]);
  final String code;
  final Object? detail;
}

class GameRepository {
  GameRepository(this._client);
  final SupabaseClient _client;

  String get _userId => _client.auth.currentUser!.id;

  // ---------- Lesen ----------

  Future<GameSnapshot> loadGame(String gameId) async {
    // Das Rack des Gegners und der Beutel kommen hier gar nicht erst an –
    // dafür sorgen die RLS-Policies, nicht dieser Code.
    final game = await _client
        .from('games')
        .select('id, board, current_seat, tiles_left, dict_version, status')
        .eq('id', gameId)
        .single();

    final players = await _client
        .from('game_players')
        .select('player_id, seat, score, profiles(display_name)')
        .eq('game_id', gameId);

    final rack = await _client
        .from('racks')
        .select('tiles')
        .eq('game_id', gameId)
        .single();

    final me = players.firstWhere((p) => p['player_id'] == _userId);
    final opponent = players.firstWhere((p) => p['player_id'] != _userId);

    return GameSnapshot(
      id: game['id'] as String,
      board: _parseBoard(game['board'] as List<dynamic>),
      rack: (rack['tiles'] as List<dynamic>).cast<String>(),
      mySeat: me['seat'] as int,
      currentSeat: game['current_seat'] as int,
      myScore: me['score'] as int,
      opponentScore: opponent['score'] as int,
      opponentName:
          (opponent['profiles'] as Map?)?['display_name'] as String? ?? 'Gegner',
      tilesLeft: game['tiles_left'] as int,
      dictVersion: game['dict_version'] as String,
      status: game['status'] as String,
    );
  }

  /// Realtime auf die games-Zeile. Reicht: jeder Zug schreibt sie an, und die
  /// Details holt sich loadGame dann frisch.
  Stream<GameSnapshot> watchGame(String gameId) {
    return _client
        .from('games')
        .stream(primaryKey: ['id'])
        .eq('id', gameId)
        .asyncMap((_) => loadGame(gameId));
  }

  static List<Tile?> _parseBoard(List<dynamic> raw) {
    final board = emptyBoard();
    for (var i = 0; i < raw.length && i < board.length; i++) {
      final cell = raw[i];
      if (cell is Map) {
        board[i] = Tile(cell['l'] as String, blank: cell['b'] as bool? ?? false);
      }
    }
    return board;
  }

  // ---------- Schreiben ----------

  Future<void> submitMove({
    required String gameId,
    required List<Placement> placements,
  }) =>
      _invoke('submit-move', {
        'game_id': gameId,
        'kind': 'play',
        'placements': placements.map((p) => p.toJson()).toList(),
      });

  Future<void> pass(String gameId) =>
      _invoke('submit-move', {'game_id': gameId, 'kind': 'pass'});

  Future<void> exchange(String gameId, List<String> tiles) =>
      _invoke('submit-move',
          {'game_id': gameId, 'kind': 'exchange', 'exchange': tiles});

  Future<void> resign(String gameId) =>
      _invoke('submit-move', {'game_id': gameId, 'kind': 'resign'});

  Future<String?> createGame({String? opponentId}) async {
    final data = await _invoke('create-game',
        opponentId == null ? {'random': true} : {'opponent_id': opponentId});
    return data['game_id'] as String?;
  }

  Future<Map<String, dynamic>> _invoke(
      String name, Map<String, dynamic> body) async {
    final response = await _client.functions.invoke(name, body: body);
    final data = (response.data as Map?)?.cast<String, dynamic>() ?? {};

    if (response.status >= 400 || data['error'] != null) {
      throw MoveRejected(
        data['error'] as String? ?? 'unknown_error',
        data['detail'],
      );
    }
    return data;
  }

  /// Meldet ein Wort, das fehlt oder nicht hätte gelten dürfen. Speist die
  /// Nachschärfung der Wortliste.
  Future<void> reportWord({
    required String word,
    required String reason,
    required String dictVersion,
    String? gameId,
  }) =>
      _client.from('word_reports').insert({
        'word': word,
        'reason': reason,
        'dict_version': dictVersion,
        'game_id': gameId,
        'reporter_id': _userId,
      });
}
