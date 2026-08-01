# Spelly – Projektstruktur

Monorepo: Client, Backend und Wörterbuch-Pipeline liegen zusammen, weil die
Spielregeln in beiden Welten identisch sein müssen. Ändert sich die
Punktewertung, sollen Client und Server im selben Commit angepasst werden.

```
spelly/
├── app/                          Flutter-Client (Android + iOS)
│   ├── pubspec.yaml
│   ├── lib/
│   │   ├── main.dart
│   │   ├── core/                 Konfiguration, Environment, DI, Theme
│   │   ├── data/                 Supabase-Client, Repositories, Modelle
│   │   ├── domain/               Dart-Portierung von rules.ts (siehe unten)
│   │   │   ├── tiles.dart
│   │   │   ├── rules.dart        playMove + previewMove für die Vorschau
│   │   │   └── dawg.dart
│   │   ├── features/
│   │   │   ├── auth/auth_page.dart      Registrierung und Anmeldung
│   │   │   ├── lobby/lobby_page.dart    Partien + Spieler:innen
│   │   │   ├── game/             Brett, Rack, Drag & Drop, Zug-Vorschau
│   │   │   └── profile/          Statistik, Einstellungen, Sprache
│   │   └── l10n/                 ARB-Dateien für App-Texte
│   ├── assets/
│   │   └── dict/de-2026.1.dawg   gebaute Wortliste, kommt aus dict/dist/
│   ├── web/                      PWA: Manifest und Push-Service-Worker
│   ├── android/                  google-services.json gehört hierhin
│   ├── ios/                      ungenutzt – iOS läuft als Web-App
│   └── test/
│       └── domain/rules_test.dart  dieselben Fälle wie die Deno-Suite
│
├── supabase/                     Backend
│   ├── config.toml
│   ├── migrations/               streng aufsteigend, nie nachträglich ändern
│   │   ├── 20260724090000_init_schema.sql
│   │   ├── 20260724090100_apply_move.sql
│   │   └── 20260724090200_notifications.sql
│   ├── functions/
│   │   ├── _shared/              von mehreren Functions genutzt
│   │   │   ├── tiles.ts          Steinwerte, Verteilung, Brettlayout
│   │   │   ├── rules.ts          Zugvalidierung und Punkte (reine Logik)
│   │   │   ├── rules.test.ts     läuft gegen shared/rules-cases.json
│   │   │   ├── dawg.ts           Wörterbuch-Lookup
│   │   │   └── onesignal.ts      Push-Versand
│   │   ├── submit-move/index.ts  Zug entgegennehmen
│   │   ├── send-push/index.ts    Warteschlange zustellen
│   │   ├── create-game/index.ts  Partie eröffnen, Beutel mischen
│   │   └── deno.json
│   └── tests/
│       └── rls_test.sql          pgTAP: prüft die Policies scharf
│
├── shared/
│   └── rules-cases.json          Regelfälle für BEIDE Implementierungen
│
├── dict/                         Wörterbuch-Pipeline (läuft nur lokal/CI)
│   ├── Makefile                  make dist/de-2026.1.dawg
│   ├── sources/                  Rohdaten, nicht eingecheckt
│   ├── scripts/
│   │   ├── expand.py             Hunspell → Vollformen
│   │   ├── filter.py             Eigennamen, Sonderzeichen, Länge
│   │   ├── build_dawg.py         Minimierung + Binärformat
│   │   └── verify.py             Stichproben gegen bekannte Wortlisten
│   └── dist/                     Ergebnis, wird nach app/assets/dict/ kopiert
│
├── docs/
│   ├── checkliste.md             abarbeitbare Reihenfolge fürs Aufsetzen
│   ├── distribution.md           APK bauen, Web-App ausliefern, Updates
│   ├── anleitung-android.md      zum Weitergeben an die Mitspielenden
│   ├── anleitung-ios.md          dito, iPhone-Fassung
│   ├── rules.md                  welche Regelvariante genau gilt
│   └── decisions/                kurze ADRs für die grossen Weichen
│
└── .github/workflows/
    ├── app.yml                   flutter analyze + test
    ├── backend.yml               deno check + pgTAP gegen lokale DB
    └── dict.yml                  Wortliste bauen, Grösse und Prüfsumme melden
```

## Drei Ablageregeln

**Migrationen sind unveränderlich.** Der Zeitstempel im Dateinamen bestimmt die
Reihenfolge. `notifications.sql` ersetzt einen Trigger aus `init_schema.sql` –
das funktioniert nur, weil sie danach läuft. Nie eine bereits ausgerollte
Migration bearbeiten, immer eine neue anlegen.

**`_shared/` ist der Unterordner mit dem Unterstrich, nicht ohne.** Supabase
deployt jeden Ordner unter `functions/` als eigene Function – ausser denen, die
mit `_` beginnen. Ohne den Unterstrich versucht die CLI, `rules.ts` als
Endpunkt zu starten.

**`rules.ts` und `app/lib/domain/rules.dart` müssen synchron bleiben.** Der
Client rechnet den Zugwert live beim Legen, der Server rechnet ihn autoritativ
nach. Zwei Implementierungen derselben Regeln sind eine Fehlerquelle – deshalb
liegen die Testfälle in `shared/rules-cases.json`, und beide Suiten lesen genau
diese Datei. Läuft eine der beiden Seiten weg, wird die CI rot, bevor jemand
eine Vorschau sieht, die der Server anders verbucht.

## Was nicht ins Repo gehört

`.env`, Service-Account-JSON, `google-services.json`, `GoogleService-Info.plist`,
Signing-Keys und `dict/sources/`. Die Wortlisten-Rohdaten sind je nach Quelle
gross und lizenzbehaftet – lieber per Skript ziehen als einchecken.
