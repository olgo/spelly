# Spelly – Projekt-Zusammenfassung für Session-Fortsetzung

## Projekt

**Spelly**: Flutter-basiertes Scrabble-ähnliches Wortlegespiel für einen Freundeskreis. Repo: `olgo/spelly` auf GitHub. Branch für alle Änderungen: `claude/gerade-gepusht-vzwgp8`.

**Stack:**
- Backend: Supabase (Projekt-Ref `wnjqjpesazhddrhcapzh`, Region eu-north-1/AWS)
- Push: OneSignal (App-ID `cec97100-f4a4-4d06-929b-80a2226fd8e4`)
- Mail: Resend, verifizierte Domain `spelly.olga-allerdings.de` (DNS bei STRATO)
- Web-Hosting geplant: GitHub Pages unter `https://olga.github.io/spelly/` (**nicht** die eigene Domain – die ist nur fürs Mailen)

## Workflow-Konventionen (wichtig für Fortsetzung)

- Vor jedem neuen Commit: `git fetch origin main && git checkout -B claude/gerade-gepusht-vzwgp8 origin/main` (Branch wird nach jedem Merge zurückgesetzt, PRs werden squash-merged)
- Jede Änderung: eigener PR, erstellt und selbst gemergt (kein Review nötig, User hat das so gewünscht)
- **Migrationen nie nachträglich ändern** – immer neue Datei mit fortlaufendem Timestamp (`YYYYMMDDHHMMSS_name.sql`)
- Ich (Claude) habe kein Supabase-CLI/Dashboard-Zugriff – User führt `supabase db push`/`functions deploy`/Dashboard-Klicks selbst aus, ich gebe die Befehle
- User testet lokal per `flutter run -d web-server --web-port=8080 --dart-define=SUPABASE_URL=https://wnjqjpesazhddrhcapzh.supabase.co --dart-define=SUPABASE_ANON_KEY=sb_publishable_tr7e21geFZyFr3qGlztQzA_gR_gqaa_` im `app/`-Ordner, öffnet `http://localhost:8080` im Browser (Chrome fehlt/nicht gewollt, daher web-server statt `-d chrome`)
- Nutzer hat wenig Fachjargon-Kenntnis, aber technisches Grundverständnis – Erklärungen entsprechend halten
- Ad-Blocker im Test-Browser blockiert OneSignal-SDK (`ERR_BLOCKED_BY_CLIENT`) – bekannt, für Gameplay-Tests unwichtig, nur für echte Push-Tests relevant

## Bisher erledigt (grob chronologisch)

1. **OneSignal statt Firebase**: komplette Migration (Web-SDK, Dart-Client, Server-Versand über OneSignal REST API statt FCM), `devices`-Tabelle gedroppt (mehrere PRs)
2. **Wörterbuch gebaut**: `app/assets/dict/de-2026.1.dawg`, 541.339 Wörter. `propernouns.txt` ist eine **Behelfslösung** (CC-BY-lizenzierte Vornamen + handgeschriebene Nach-/Ortsnamen), keine echte Wiktionary-Ableitung (Wiktionary in der Bau-Umgebung durch Netzwerk-Policy blockiert)
3. **Datenbank aufgesetzt**: Migrationen, `supabase test db` – dabei **5 echte Bugs gefunden und gefixt**: Testdaten-Konflikt mit `handle_new_user`, fehlende Vault-Einträge im Test, drei fehlende `GRANT`-Statements (Supabase-Plattform-Bootstrap fehlt lokal). Storage-Bucket `dict` + Vault-Einträge (`push_function_url`, `service_role_key`) eingerichtet
4. **Mailversand-Hin-und-her**: zuerst wegen fehlender Domain `Confirm email` deaktiviert und Auth-UI entsprechend umgebaut (E-Mail-Feld raus, Zufalls-Code-Konzept) – dann stellte sich raus, User hat doch eine Domain (`olga-allerdings.de`) → **alles per `git revert` zurückgebaut** auf echten Mailversand. Resend-Domain `spelly.olga-allerdings.de` ist jetzt verifiziert (DKIM + SPF-TXT bei STRATO eingetragen, MX-Record bewusst weggelassen – ging bei STRATO nicht sauber für die Subdomain, ist nur ein optionaler Zustellrate-Bonus)
5. **Checkliste** (`docs/checkliste.md`) laufend aktualisiert, dokumentiert Ist-Stand und Abweichungen
6. **Lokales Testen aufgesetzt und dabei mehrere echte Bugs gefunden+gefixt**:
   - CORS: `x-client-info`-Header fehlte in `create-game`/`submit-move` → Browser blockierte Aufrufe komplett
   - `respond_invitation()`: SQLSTATE 42804 (datatype_mismatch) – `CASE`-Ausdruck ohne expliziten Enum-Cast
   - `_shared/dawg.ts`: fehlender `apikey`-Header beim direkten Storage-Fetch → 400 beim Wörterbuch-Laden
   - Realtime für `games`-Tabelle war nie freigeschaltet (`alter publication supabase_realtime add table games`)
   - `GameController.submit()`: `_pending` wurde geleert ohne `_recompute()` → `_preview` blieb kurz inkonsistent → Absturz in `_PreviewChip` (`pending.last` auf leerer Liste)
   - Fehlerbehandlung fehlte komplett bei mehreren Buttons (Herausfordern, Abmelden, Passen, watchGame-Stream) – Fehler verschwanden stillschweigend statt sichtbar zu werden. Jetzt überall try/catch mit Nutzer-Feedback

Alle Fixes sind gemergt, PRs #1 bis #22.

## Aktueller Stand / letzter offener Punkt

User hat gerade **erneut `supabase db push`** ausgeführt, um zu prüfen, ob der Realtime-`channelError` (Live-Updates beim Gegnerzug) jetzt behoben ist. **Antwort/Test-Ergebnis steht noch aus** – das ist der nächste Schritt: prüfen, ob Realtime jetzt funktioniert (zwei Accounts, Zug auf einer Seite, kommt er ohne manuelles Neuladen bei der anderen Seite an?).

## Noch offen laut Checkliste (danach)

| Abschnitt | Was fehlt |
|---|---|
| 4. Anmeldung | *Authentication → URL Configuration*: Site URL `https://olga.github.io/spelly/`, Redirect URLs (`https://olga.github.io/spelly/**` und `spelly://login-callback`) – Status unklar, ob schon eingetragen |
| 5. OneSignal/Android | Plattform-Ordner (`flutter create --org de.spelly --project-name spelly --platforms=android,web .`), Firebase-Projekt für OneSignal-Android-Push, `google-services.json`, `AndroidManifest.xml` anpassen, OneSignal-Web-Push-Plattform im Dashboard konfigurieren (Site-URL) |
| 8. Prüfläufe | App-Icons erzeugen, `flutter analyze`, `flutter test` |
| 9. Web ausliefern | `flutter build web --release --base-href /spelly/ --dart-define=...` (Base-href **nötig**, da unter `/spelly/`-Unterpfad!), Ergebnis auf `gh-pages`-Branch pushen, GitHub Pages in Repo-Settings aktivieren |
| 10. APK bauen | Signierschlüssel, `flutter build apk --release` |
| 11–12. Versionsstand/Verschicken | `app_release`-Tabelle befüllen, Anleitungen (`docs/anleitung-android.md`/`-ios.md`) mit echten Links füllen, testen, verschicken |

## Bekannte, akzeptierte Lücken (laut `docs/checkliste.md`, Tabelle "Was im Code noch fehlt")

Passwort-Zurücksetzen-Bildschirm, Versionsprüfung im Client, Partieende-Bildschirm, Steine-tauschen-Knopf, Wort-melden-Knopf, Mehrsprachigkeit – alles bewusst nicht blockierend für den ersten Versand.
