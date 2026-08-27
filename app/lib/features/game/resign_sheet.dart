import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Fragt nach, ob die Partie wirklich aufgegeben werden soll. Liefert `true`
/// bei Bestätigung, sonst `null` – anders als beim Tauschen gibt es hier
/// nichts auszuwählen, nur eine Entscheidung, die sich nicht zurücknehmen
/// lässt.
Future<bool?> showResignSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: Palette.graphite,
    builder: (context) => const _ResignSheet(),
  );
}

class _ResignSheet extends StatelessWidget {
  const _ResignSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Partie aufgeben?',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Die Partie endet sofort, der Gegner gewinnt. Das lässt sich '
              'nicht rückgängig machen.',
              style: Theme.of(context).textTheme.labelSmall,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Abbrechen'),
                ),
                const Spacer(),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Palette.warn,
                    foregroundColor: Palette.boneInk,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Aufgeben'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
