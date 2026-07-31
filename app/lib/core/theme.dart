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
  static const graphite = Color(0xFF16232C); // App-Hintergrund
  static const boardInk = Color(0xFF0E1B24); // Brettfläche
  static const cellSlate = Color(0xFF1A2C38); // leeres Feld
  static const hairline = Color(0xFF2A3E4B);

  static const bone = Color(0xFFE9DFC9); // Steinfläche
  static const boneShade = Color(0xFFC9BC9F); // Steinkante
  static const boneInk = Color(0xFF23313A); // Buchstabe auf dem Stein

  static const letterDouble = Color(0xFF27505F);
  static const letterTriple = Color(0xFF357C88);
  static const wordDouble = Color(0xFF6E4650);
  static const wordTriple = Color(0xFF96513F);

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
/// erst eine Legende suchen muss.
String premiumLabel(String code) => switch (code) {
      'd' => '2×B',
      't' => '3×B',
      'D' => '2×W',
      'T' => '3×W',
      _ => '',
    };
