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

        return Scaffold(
          appBar: AppBar(
            backgroundColor: Palette.graphite,
            elevation: 0,
            leadingWidth: 180,
            leading: TextButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back, size: 18, color: Palette.text),
              label: const Text(
                'Zurück zur Lobby',
                style: TextStyle(color: Palette.text),
              ),
            ),
          ),
          body: SafeArea(
            child: snapshot == null
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      _ScoreBar(controller: _controller),
                      Expanded(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(8),
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
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
      child: Row(
        children: [
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
            fontSize: 24,
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
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Column(
        children: [
          if (controller.lastError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                moveMessage(controller.lastError!),
                style: const TextStyle(color: Palette.warn, fontSize: 12.5),
              ),
            ),
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
        ],
      ),
    );
  }
}
