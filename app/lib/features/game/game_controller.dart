import 'package:flutter/foundation.dart';

import '../../data/game_repository.dart';
import '../../domain/dawg.dart';
import '../../domain/rules.dart';

/// Hält den Zustand einer offenen Partie und rechnet die Vorschau.
///
/// Der springende Punkt: [preview] wird bei jeder Änderung der gelegten Steine
/// neu berechnet, lokal, ohne Netz. Der Server rechnet beim Absenden dasselbe
/// noch einmal und hat das letzte Wort – die Vorschau ist eine Anzeige, keine
/// Entscheidung.
class GameController extends ChangeNotifier {
  GameController(this._repo, this._gameId);

  final GameRepository _repo;
  final String _gameId;

  GameSnapshot? _snapshot;
  WordSource _dict = const EmptyWordSource();
  bool _dictReady = false;

  final List<Placement> _pending = [];
  MovePreview? _preview;
  bool _submitting = false;
  String? _lastError;

  GameSnapshot? get snapshot => _snapshot;
  List<Placement> get pending => List.unmodifiable(_pending);
  MovePreview? get preview => _preview;
  bool get submitting => _submitting;
  bool get dictReady => _dictReady;
  String? get lastError => _lastError;

  bool get isMyTurn => _snapshot?.isMyTurn ?? false;

  /// Steine, die gerade noch auf dem Rack liegen – also ohne die, die schon
  /// auf dem Brett abgelegt wurden.
  List<String> get availableRack {
    final rack = List<String>.of(_snapshot?.rack ?? const []);
    for (final p in _pending) {
      final need = p.blank ? '?' : p.letter;
      rack.remove(need);
    }
    return rack;
  }

  /// Das Brett inklusive der noch nicht abgeschickten Steine.
  List<Tile?> get displayBoard {
    final board = List<Tile?>.of(_snapshot?.board ?? emptyBoard());
    for (final p in _pending) {
      board[p.index] = Tile(p.letter, blank: p.blank);
    }
    return board;
  }

  Set<int> get pendingIndices => _pending.map((p) => p.index).toSet();

  Future<void> start() async {
    _snapshot = await _repo.loadGame(_gameId);
    notifyListeners();

    // Wortliste nachladen: fünf Megabyte sollen das erste Bild nicht aufhalten.
    // Bis sie da ist, meldet die Vorschau "prüfe noch" statt einer Zahl.
    _dict = await Dawg.load(_snapshot!.dictVersion);
    _dictReady = true;
    _recompute();

    _repo.watchGame(_gameId).listen((snapshot) {
      _snapshot = snapshot;
      // Ein Zug des Gegners macht eigene Ablagen hinfällig.
      if (_pending.isNotEmpty && !snapshot.isMyTurn) _pending.clear();
      _recompute();
    });
  }

  // ---------- Steine bewegen ----------

  void place(Placement placement) {
    if (!isMyTurn) return;
    if (_snapshot!.board[placement.index] != null) return;
    _pending.removeWhere((p) => p.index == placement.index);
    _pending.add(placement);
    _recompute();
  }

  void pickUp(int index) {
    _pending.removeWhere((p) => p.index == index);
    _recompute();
  }

  void clearPending() {
    _pending.clear();
    _recompute();
  }

  void _recompute() {
    if (_pending.isEmpty) {
      _preview = null;
    } else if (!_dictReady) {
      _preview = const MovePreview.invalid('dict_loading');
    } else {
      _preview = previewMove(
        _snapshot!.board,
        _snapshot!.rack,
        _pending,
        _dict,
      );
    }
    notifyListeners();
  }

  // ---------- Zug abschicken ----------

  Future<bool> submit() async {
    if (_submitting || _pending.isEmpty) return false;
    _submitting = true;
    _lastError = null;
    notifyListeners();

    try {
      await _repo.submitMove(gameId: _gameId, placements: _pending);
      _pending.clear();
      _snapshot = await _repo.loadGame(_gameId);
      return true;
    } on MoveRejected catch (e) {
      // Der Server hat anders entschieden als die Vorschau. Das darf nicht
      // vorkommen; wenn doch, ist es ein Hinweis auf auseinandergelaufene
      // Regelstände und gehört gemeldet.
      _lastError = e.code;
      if (e.code == 'stale_turn') {
        _pending.clear();
        _snapshot = await _repo.loadGame(_gameId);
      }
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<void> pass() async {
    _pending.clear();
    await _repo.pass(_gameId);
    _snapshot = await _repo.loadGame(_gameId);
    notifyListeners();
  }
}
