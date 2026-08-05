import 'package:flutter/material.dart';

import '../../core/messages.dart';
import '../../core/theme.dart';
import '../../data/game_repository.dart';
import 'board_view.dart';
import 'game_controller.dart';
import 'rack_view.dart';

class GamePage extends StatefulWidget {
  const GamePage({super.key, required this.repository, required this.gameId});

  final GameRepository repository;
  final String gameId;

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final GameController _controller =
      GameController(widget.repository, widget.gameId);

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final snapshot = _controller.snapshot;

        // Keine AppBar: Ihre 56 Punkt sind auf einem Telefon der grösste
        // Einzelposten, der dem Brett fehlt – im Browserfenster, wo Safari
        // sich oben und unten schon gut hundert Punkt nimmt, entscheidet das
        // darüber, ob das Brett die volle Breite bekommt. Der Weg zurück
        // steckt jetzt als Pfeil in der Punktzeile.
        return Scaffold(
          body: SafeArea(
            child: snapshot == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _ScoreBar(controller: _controller),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: BoardView(controller: _controller),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: RackView(controller: _controller),
                      ),
                      _Actions(controller: _controller),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.snapshot!;
    final turnLabel = s.status != 'active'
        ? 'Partie beendet'
        : controller.isMyTurn
            ? 'Du bist am Zug'
            : '${s.opponentName} ist am Zug';

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 14, 4),
      child: Row(
        children: [
          // Der Weg zurück in die Lobby. Fest auf 40 Punkt begrenzt – ein
          // IconButton bringt sonst 48 mit und macht die Zeile höher, als
          // die Punktestände sie ohnehin schon machen.
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
            iconSize: 22,
            color: Palette.textDim,
            tooltip: 'Zurück zur Lobby',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
          ),
          const SizedBox(width: 6),
          _Score(label: 'Du', value: s.myScore, active: controller.isMyTurn),
          const SizedBox(width: 18),
          _Score(
            label: s.opponentName,
            value: s.opponentScore,
            active: !controller.isMyTurn && s.status == 'active',
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(turnLabel, style: Theme.of(context).textTheme.labelSmall),
              const SizedBox(height: 2),
              Text('${s.tilesLeft} im Beutel',
                  style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _Score extends StatelessWidget {
  const _Score({
    required this.label,
    required this.value,
    required this.active,
  });

  final String label;
  final int value;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: active ? Palette.signal : Palette.textDim,
                fontSize: 10,
              ),
        ),
        Text(
          '$value',
          style: TextStyle(
            color: active ? Palette.text : Palette.textDim,
            fontSize: 21,
            height: 1.1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ],
    );
  }
}

class _Actions extends StatelessWidget {
  const _Actions({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;
    final canSubmit = preview?.isValid == true && !controller.submitting;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Column(
        children: [
          Row(
            children: [
              TextButton(
                onPressed: controller.pending.isEmpty
                    ? null
                    : controller.clearPending,
                child: const Text('Zurücknehmen'),
              ),
              const Spacer(),
              TextButton(
                onPressed: controller.isMyTurn ? controller.pass : null,
                child: const Text('Passen'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Palette.signal,
                  foregroundColor: Palette.boneInk,
                  disabledBackgroundColor: Palette.hairline,
                  disabledForegroundColor: Palette.textDim,
                ),
                onPressed: canSubmit ? () => controller.submit() : null,
                child: Text(
                  // Der Knopf trägt den Wert, den die Vorschau zeigt. Nach dem
                  // Tippen heisst es dieselbe Zahl, kein neuer Begriff.
                  canSubmit ? 'Legen für ${preview!.score}' : 'Legen',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _StatusLine(controller: controller),
        ],
      ),
    );
  }
}

/// Der einzige Ort, an dem das Spiel sagt, was gerade nicht geht. Feste Höhe,
/// damit das Auftauchen einer Meldung nicht das ganze Brett verschiebt – und
/// unter den Knöpfen statt auf dem Brett, wo der Kasten früher Steine verdeckt
/// hat.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.controller});
  final GameController controller;

  @override
  Widget build(BuildContext context) {
    final preview = controller.preview;

    String? text;
    Color colour = Palette.warn;

    if (controller.lastError != null) {
      text = moveMessage(controller.lastError!);
    } else if (preview != null &&
        !preview.isValid &&
        showsWhilePlacing(preview.error!)) {
      text = moveMessage(preview.error!, preview.detail);
    } else if (preview != null && preview.isValid && preview.words.length > 1) {
      // Bei einem einzigen Wort steht die Zahl schon auf dem Knopf. Erst wenn
      // mehrere Wörter zusammenkommen, ist die Aufstellung eine eigene
      // Auskunft: dann sieht man, woher die Punkte stammen.
      text = preview.words.map((w) => '${w.word} ${w.score}').join(' · ');
      colour = Palette.signal;
    }

    return SizedBox(
      height: 18,
      width: double.infinity,
      child: text == null
          ? null
          : Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.fade,
              style: TextStyle(color: colour, fontSize: 12, height: 1.2),
            ),
    );
  }
}
