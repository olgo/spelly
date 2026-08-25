import 'package:flutter/material.dart';

/// Farbwelt: kaltes Tintenblau für Brett und Rahmen, warmes Knochenweiss für
/// die Steine. Der Kontrast zwischen kaltem Untergrund und warmem Stein macht
/// auf einen Blick klar, was liegt und was Feld ist – wichtiger als Dekor,
/// wenn 225 Felder auf ein Telefondisplay müssen.
///
/// Die Prämienfelder sind bewusst zurückgenommene Tuschetöne statt der
/// üblichen Signalfarben. Sie sollen die Steine nicht überstrahlen; die
/// einzige laute Farbe im Spiel gehört der Zugvorschau.
abstract final class Palette {
  // Teal statt Navy – dem App-Icon angenähert (Grundton, nicht die volle
  // Sättigung: Rot und Teal liegen nahe der Komplementärachse, ein Rotton,
  // der auf Navy gedämpft wirkt, würde auf Teal automatisch kräftiger
  // wirken, siehe wordDouble/wordTriple unten).
  static const graphite = Color(0xFF3F1362); // App-Hintergrund
  static const boardInk = Color(0xFF1B2522); // Brettfläche
  static const cellSlate = Color(0xFF5D1954); // leeres Feld
  static const hairline = Color(0xFF365471);

  static const bone = Color(0xFFE9DFC9); // Steinfläche
  static const boneShade = Color(0xFFC9BC9F); // Steinkante
  static const boneInk = Color(0xFF23313A); // Buchstabe auf dem Stein

  static const letterDouble = Color(0xFF285868);
  static const letterTriple = Color(0xFF3B85A0);
  static const wordDouble = Color(0xFF8A5886);
  static const wordTriple = Color(0xFFB323B6);

  static const signal = Color(0xFFF0B24A); // gültige Vorschau
  static const warn = Color(0xFFCF6155); // ungültige Vorschau
  static const text = Color(0xFFE4EAEE);
  static const textDim = Color(0xFF8FA3AF);
}

abstract final class Metrics {
  static const boardPadding = 8.0;
  static const cellGap = 1.5;
  static const tileRadius = 3.0;
}

/// Die Steine tragen die Persönlichkeit des Spiels. Vorgesehen ist eine
/// schmale Grotesk mit kräftigen Versalien; solange keine Schrift gebündelt
/// ist, trägt die Systemschrift mit engerem Satz.
ThemeData buildTheme() {
  const base = ColorScheme.dark(
    primary: Palette.signal,
    surface: Palette.graphite,
    error: Palette.warn,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: base,
    scaffoldBackgroundColor: Palette.graphite,
    textTheme: const TextTheme(
      titleMedium: TextStyle(
        color: Palette.text,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
      ),
      bodyMedium: TextStyle(color: Palette.text),
      labelSmall: TextStyle(
        color: Palette.textDim,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

Color premiumColour(String code) => switch (code) {
      'd' => Palette.letterDouble,
      't' => Palette.letterTriple,
      'D' => Palette.wordDouble,
      'T' => Palette.wordTriple,
      _ => Palette.cellSlate,
    };

/// Kurzschrift auf leeren Prämienfeldern. Deutsch abgekürzt, damit niemand
/// erst eine Legende suchen muss. Ohne Mal-Zeichen: zwei Zeichen statt drei
/// lassen jedem Zeichen die Hälfte mehr Platz – auf einem Feld von zwanzig
/// Pixeln ist das der Unterschied zwischen lesbar und geraten.
String premiumLabel(String code) => switch (code) {
      'd' => '2B',
      't' => '3B',
      'D' => '2W',
      'T' => '3W',
      _ => '',
    };
