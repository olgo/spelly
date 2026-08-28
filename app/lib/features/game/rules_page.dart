import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Die Spielanleitung. Eigene Seite statt Bottom-Sheet: Die kurzen Sheets
/// (`exchange_sheet.dart`, `resign_sheet.dart`) sind für Ja/Nein-Fragen
/// gebaut (`mainAxisSize: min`, kein Scrollen) – für Fliesstext braucht es
/// eine `AppBar` und `SingleChildScrollView`. Die Enge, die `game_page.dart`
/// bewusst ohne `AppBar` löst, gilt nur fürs Spielbrett, nicht für eine
/// Lese-Unterseite.
class RulesPage extends StatelessWidget {
  const RulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Palette.graphite,
        title: const Text('Spielanleitung'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: const [
            _Section(
              title: 'Ziel',
              children: [
                _P(
                  'Ihr legt abwechselnd Wörter aufs Brett und sammelt dafür '
                  'Punkte. Wer am Ende die höhere Punktzahl hat, gewinnt.',
                ),
              ],
            ),
            _Section(
              title: 'Ein Zug',
              children: [
                _P(
                  'Steine vom Rack aufs Brett ziehen. Solange noch nichts '
                  'abgeschickt ist, zeigt der „Legen"-Knopf schon die '
                  'Punktzahl der Vorschau. Gefällt der Zug, auf „Legen" '
                  'tippen – erst dann zählt er wirklich.',
                ),
                _P(
                  'Der erste Zug der Partie muss über das Mittelfeld '
                  '(markiert mit ★) gehen und mindestens zwei Steine lang '
                  'sein.',
                ),
                _P(
                  'Jeder spätere Zug muss an ein schon liegendes Wort '
                  'anschliessen: gerade Linie, keine Lücke zwischen den '
                  'Steinen.',
                ),
              ],
            ),
            _Section(
              title: 'Bonusfelder',
              children: [
                _P(
                  'Ein Bonus zählt nur, wenn ein Stein zum ersten Mal auf '
                  'dem Feld landet – liegt schon einer dort, gilt der '
                  'normale Wert.',
                ),
                _Legend(),
              ],
            ),
            _Section(
              title: 'Blankos',
              children: [
                _P(
                  'Ein Blanko-Stein steht für einen beliebigen Buchstaben – '
                  'antippen, um ihn festzulegen. Er zählt dafür immer 0 '
                  'Punkte, egal welcher Buchstabe.',
                ),
              ],
            ),
            _Section(
              title: 'Bonus für volle Hand',
              children: [
                _P(
                  'Wer alle sieben Steine in einem einzigen Zug loswird, '
                  'bekommt 50 Punkte extra.',
                ),
              ],
            ),
            _Section(
              title: 'Was die Knöpfe bedeuten',
              children: [
                _P('Pfeil oben links – zurück zur Lobby.'),
                _P(
                  '„Zurücknehmen" – legt Steine, die schon aufs Brett '
                  'gezogen, aber noch nicht abgeschickt sind, zurück aufs '
                  'Rack.',
                ),
                _P(
                  'Mischen-Symbol (die beiden gekreuzten Pfeile) – bringt '
                  'die Reihenfolge der Rack-Steine durcheinander. Steine '
                  'lassen sich ausserdem jederzeit von Hand ziehen, um sie '
                  'selbst umzusortieren – beides hilft, ein Wort zu '
                  'entdecken, ohne etwas aufs Brett zu legen.',
                ),
                _P(
                  '„⋮"-Menü – Steine tauschen, Passen, Aufgeben und diese '
                  'Spielanleitung.',
                ),
                _P('„Legen" – schickt den aktuellen Zug ab.'),
              ],
            ),
            _Section(
              title: 'Passen, Tauschen, Aufgeben',
              children: [
                _P(
                  '„Passen" beendet den Zug ohne zu legen – nur am eigenen '
                  'Zug möglich.',
                ),
                _P(
                  '„Steine tauschen" legt gewählte Steine zurück in den '
                  'Beutel und zieht genauso viele neu; braucht mindestens '
                  'sieben Steine im Beutel und beendet ebenfalls den Zug.',
                ),
                _P(
                  '„Aufgeben" beendet die Partie sofort, der Gegner '
                  'gewinnt – anders als Passen geht das jederzeit, auch '
                  'wenn der Gegner am Zug ist.',
                ),
              ],
            ),
            _Section(
              title: 'Wie eine Partie endet',
              children: [
                _P('Jemand gibt auf – der Gegner gewinnt sofort.'),
                _P(
                  'Der Beutel ist leer und wer am Zug war, legt seinen '
                  'letzten Stein – die restlichen Steine des Gegners '
                  'werden von dessen Punktzahl abgezogen und der '
                  'fertigspielenden Person gutgeschrieben.',
                ),
                _P(
                  'Sechs Nullzüge in Folge (Passen oder Tauschen, egal von '
                  'wem) – jede Person verliert den Wert der eigenen noch '
                  'übrigen Steine.',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _P extends StatelessWidget {
  const _P(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(height: 1.4, color: Palette.text),
      ),
    );
  }
}

/// Die vier Bonusfelder mit denselben Farben und Kürzeln wie auf dem echten
/// Brett (`premiumColour`/`premiumLabel` aus theme.dart) – nachgebaut statt
/// neu erfunden, damit die Erklärung zu dem passt, was man tatsächlich sieht.
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    const rows = [
      ('d', 'Buchstabenwert doppelt'),
      ('t', 'Buchstabenwert dreifach'),
      ('D', 'Wortwert doppelt'),
      ('T', 'Wortwert dreifach'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (code, meaning) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: premiumColour(code),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    premiumLabel(code),
                    style: const TextStyle(
                      color: Palette.text,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  meaning,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Palette.text),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
