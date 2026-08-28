import 'dart:async';

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

  /// Tauschen geht nur, solange im Beutel noch ein volles Rack liegt. Dieselbe
  /// Schwelle prüft der Server (`bag_too_small` in `submit-move/index.ts`) –
  /// hier steht sie, damit der Menüpunkt gar nicht erst anklickbar ist.
  static const minBagForExchange = 7;

  GameSnapshot? _snapshot;
  WordSource _dict = const EmptyWordSource();
  bool _dictReady = false;

  /// Die selbst gewählte Reihenfolge der eigenen Steine, `null` heisst: so wie
  /// der Server sie schickt. Reine Anzeige – die Regelprüfung zählt die Steine
  /// als Menge (`rules.dart`), Reihenfolge trägt dort keine Bedeutung.
  List<String>? _rackOrder;

  final List<Placement> _pending = [];
  MovePreview? _preview;
  bool _submitting = false;
  String? _lastError;

  /// Felder, die im letzten Zug neu dazukamen – eigener oder gegnerischer.
  /// Nur für das kurze Aufblitzen in board_view.dart, sonst ohne Bedeutung.
  Set<int> _flashIndices = {};
  Timer? _flashTimer;

  GameSnapshot? get snapshot => _snapshot;
  List<Placement> get pending => List.unmodifiable(_pending);
  MovePreview? get preview => _preview;
  bool get submitting => _submitting;
  bool get dictReady => _dictReady;
  String? get lastError => _lastError;
  Set<int> get flashIndices => _flashIndices;

  bool get isMyTurn => _snapshot?.isMyTurn ?? false;

  @override
  void dispose() {
    _flashTimer?.cancel();
    super.dispose();
  }

  /// Ob der Beutel noch genug für einen Tausch hergibt.
  bool get canExchange =>
      isMyTurn &&
      !_submitting &&
      (_snapshot?.tilesLeft ?? 0) >= minBagForExchange;

  /// Steine, die gerade noch auf dem Rack liegen – also ohne die, die schon
  /// auf dem Brett abgelegt wurden.
  List<String> get availableRack {
    final rack = List<String>.of(_rackOrder ?? _snapshot?.rack ?? const []);
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

  /// Der einzige Ort, an dem ein neuer Spielstand ankommt.
  ///
  /// Die gemischte Reihenfolge überlebt, solange dieselben Steine im Rack
  /// liegen: Ein Zug des Gegners löst hier ebenfalls eine Aktualisierung aus,
  /// und der darf die eigene Sortierung nicht umwerfen. Erst wenn nachgezogen
  /// wurde, sind es andere Steine und die alte Reihenfolge hinfällig.
  void _adopt(GameSnapshot next) {
    final order = _rackOrder;
    _snapshot = next;
    if (order == null || !_sameTiles(order, next.rack)) _rackOrder = null;
  }

  static bool _sameTiles(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final rest = List<String>.of(b);
    for (final tile in a) {
      if (!rest.remove(tile)) return false;
    }
    return true;
  }

  Future<void> start() async {
    _adopt(await _repo.loadGame(_gameId));
    notifyListeners();

    // Wortliste nachladen: fünf Megabyte sollen das erste Bild nicht aufhalten.
    // Bis sie da ist, meldet die Vorschau "prüfe noch" statt einer Zahl.
    _dict = await Dawg.load(_snapshot!.dictVersion);
    _dictReady = true;
    _recompute();

    _repo.watchGame(_gameId).listen(
      (snapshot) {
        final beforeBoard = _snapshot?.board;
        _adopt(snapshot);
        // Ein Zug des Gegners macht eigene Ablagen hinfällig.
        if (_pending.isNotEmpty && !snapshot.isMyTurn) _pending.clear();
        _recompute();
        _flashNewTiles(beforeBoard, snapshot.board);
      },
      // Ein einzelnes fehlgeschlagenes Update darf die Verbindung nicht
      // stillschweigend abwürgen - beim nächsten Zug kommt sonst nie wieder
      // eine Aktualisierung an.
      onError: (Object error) {
        debugPrint('watchGame update failed: $error');
      },
    );
  }

  // ---------- Steine bewegen ----------

  void place(Placement placement) {
    if (!isMyTurn) return;
    if (_snapshot!.board[placement.index] != null) return;
    _pending.removeWhere((p) => p.index == placement.index);
    _pending.add(placement);
    _clearLastError();
    _recompute();
  }

  void pickUp(int index) {
    _pending.removeWhere((p) => p.index == index);
    _clearLastError();
    _recompute();
  }

  /// Wer die Steine umbaut, hat den abgelehnten Zug hinter sich gelassen – die
  /// Meldung dazu darf nicht stehen bleiben, während schon ein neuer entsteht.
  ///
  /// Bewusst hier und nicht in [_recompute]: [submit] setzt den Fehler und
  /// räumt auf dem stale_turn-Pfad danach die Steine ab, würde ihn also über
  /// [_recompute] sofort wieder löschen.
  void _clearLastError() => _lastError = null;

  /// Einen schon gelegten Stein auf ein anderes Feld schieben. Ein Schritt,
  /// nicht Aufnehmen-und-Legen: sonst rechnet die Vorschau zweimal, und zieht
  /// der Gegner zufällig dazwischen, steigt [place] aus – der Stein wäre dann
  /// vom alten Feld verschwunden, ohne je auf dem neuen anzukommen.
  void move(int from, Placement to) {
    if (!isMyTurn) return;
    if (from == to.index) return;
    if (_snapshot!.board[to.index] != null) return;

    final at = _pending.indexWhere((p) => p.index == from);
    if (at < 0) return;

    _pending.removeAt(at);
    _pending.removeWhere((p) => p.index == to.index);
    _pending.add(to);
    _clearLastError();
    _recompute();
  }

  void clearPending() {
    _pending.clear();
    _clearLastError();
    _recompute();
  }

  /// Die eigenen Steine neu anordnen. Ändert nichts am Spiel – aber ein Wort
  /// springt einen in anderer Reihenfolge oft erst an.
  ///
  /// Auch erlaubt, während der Gegner am Zug ist: Genau dann sitzt man davor
  /// und sucht.
  void shuffleRack() {
    final current = _rackOrder ?? _snapshot?.rack;
    if (current == null || current.length < 2) return;

    // Ein Knopf, der manchmal nichts tut, wirkt kaputt. Bei zwei Steinen
    // trifft der Zufall in der Hälfte der Fälle die alte Reihenfolge, deshalb
    // ein paar Anläufe – gleiche Buchstaben bleiben dabei ununterscheidbar,
    // das ist dann aber auch egal.
    final mixed = List<String>.of(current);
    for (var attempt = 0; attempt < 5; attempt++) {
      mixed.shuffle();
      if (!_sameOrder(mixed, current)) break;
    }

    _rackOrder = mixed;
    notifyListeners();
  }

  static bool _sameOrder(List<String> a, List<String> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Sortiert die sichtbaren Rack-Steine um. [from]/[to] sind Positionen in
  /// [availableRack] (was tatsächlich gerendert wird), nicht in [_rackOrder]
  /// – abgelegte (pending) Steine sind unsichtbar und werden hinten
  /// angehängt, sobald man sie zurücknimmt. Ihre genaue Position dort spielt
  /// keine Rolle: Reine Anzeige, wie schon bei [_rackOrder] dokumentiert.
  ///
  /// Auch erlaubt, während der Gegner am Zug ist – wie [shuffleRack]: Genau
  /// dann sitzt man davor und sucht ein Wort.
  void reorderRack(int from, int to) {
    final visible = List<String>.of(availableRack);
    if (from < 0 ||
        from >= visible.length ||
        to < 0 ||
        to >= visible.length ||
        from == to) {
      return;
    }
    visible.insert(to, visible.removeAt(from));

    final hidden = <String>[];
    final source = List<String>.of(_rackOrder ?? _snapshot?.rack ?? const []);
    for (final p in _pending) {
      final need = p.blank ? '?' : p.letter;
      final at = source.indexOf(need);
      if (at != -1) hidden.add(source.removeAt(at));
    }
    _rackOrder = [...visible, ...hidden];
    notifyListeners();
  }

  /// Markiert Felder, die zwischen [before] und [after] von leer auf belegt
  /// gewechselt sind, für ein kurzes Aufblitzen – läuft nach jedem Zug, dem
  /// eigenen wie dem des Gegners (siehe [start] und [submit]).
  void _flashNewTiles(List<Tile?>? before, List<Tile?> after) {
    if (before == null) return;
    final changed = <int>{
      for (var i = 0; i < after.length; i++)
        if (before[i] == null && after[i] != null) i,
    };
    // Nach einem eigenen Zug liefert das Realtime-Update denselben Stand oft
    // noch einmal – dann ist der Vergleich schon leer, kein doppeltes
    // Aufblitzen.
    if (changed.isEmpty) return;

    _flashTimer?.cancel();
    _flashIndices = changed;
    notifyListeners();
    _flashTimer = Timer(const Duration(milliseconds: 1000), () {
      _flashIndices = {};
      notifyListeners();
    });
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

    final beforeBoard = _snapshot?.board;
    try {
      await _repo.submitMove(gameId: _gameId, placements: _pending);
      _pending.clear();
      _recompute();
      final next = await _repo.loadGame(_gameId);
      _adopt(next);
      _flashNewTiles(beforeBoard, next.board);
      return true;
    } on MoveRejected catch (e) {
      // Der Server hat anders entschieden als die Vorschau. Das darf nicht
      // vorkommen; wenn doch, ist es ein Hinweis auf auseinandergelaufene
      // Regelstände und gehört gemeldet.
      _lastError = e.code;
      if (e.code == 'stale_turn') {
        _pending.clear();
        _recompute();
        _adopt(await _repo.loadGame(_gameId));
      }
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  /// Steine zurück in den Beutel, genauso viele nachziehen, Zug vorbei.
  ///
  /// Rechnen tut das der Server: Er zieht erst nach und legt die abgegebenen
  /// Steine danach zurück, sonst zöge man die eigenen wieder. Hier wird nur
  /// gefragt und das Ergebnis übernommen.
  Future<bool> exchange(List<String> tiles) async {
    if (_submitting || tiles.isEmpty) return false;
    _submitting = true;
    _lastError = null;
    // Ein Tausch beendet den Zug – was auf dem Brett liegt, wird damit
    // hinfällig und muss weg, bevor der neue Stand ankommt.
    _pending.clear();
    notifyListeners();

    try {
      await _repo.exchange(_gameId, tiles);
      _adopt(await _repo.loadGame(_gameId));
      _recompute();
      return true;
    } on MoveRejected catch (e) {
      _lastError = e.code;
      return false;
    } catch (_) {
      _lastError = 'exchange_failed';
      return false;
    } finally {
      _submitting = false;
      notifyListeners();
    }
  }

  Future<void> pass() async {
    _pending.clear();
    _lastError = null;
    try {
      await _repo.pass(_gameId);
      _adopt(await _repo.loadGame(_gameId));
    } catch (_) {
      _lastError = 'pass_failed';
    } finally {
      notifyListeners();
    }
  }

  /// Beendet die Partie sofort, der Gegner gewinnt. Anders als [pass] geht
  /// das zu jedem Zeitpunkt, nicht nur am eigenen Zug – `submit-move`
  /// verzichtet für `resign` bewusst auf den Zugzwang.
  Future<void> resign() async {
    _pending.clear();
    _lastError = null;
    try {
      await _repo.resign(_gameId);
      _adopt(await _repo.loadGame(_gameId));
    } catch (_) {
      _lastError = 'resign_failed';
    } finally {
      notifyListeners();
    }
  }
}
