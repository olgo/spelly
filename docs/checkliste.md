# Checkliste: von hier bis zum verschickten Link

Reihenfolge ist nicht beliebig – jeder Abschnitt braucht Ergebnisse aus dem
vorherigen. Grob gerechnet ein langer Nachmittag, wenn nichts klemmt.

**Was du nicht brauchst:** keinen Mac, kein Apple-Entwicklerkonto, keinen
APNs-Schlüssel. iOS läuft als Web-App, und Web-Push geht über OneSignal. Bauen
lässt sich alles unter Linux oder Windows.

---

## 0. Werkzeuge auf deinem Rechner

- [ ] Flutter SDK (`flutter doctor` soll für Android und Web grün sein)
- [ ] Android SDK – kommt mit Android Studio, `flutter doctor` sagt dir, was fehlt
- [ ] JDK (für `keytool`, steckt in Android Studio)
- [ ] Python 3.11+ (Wörterbuch-Pipeline)
- [ ] Supabase CLI
- [ ] Deno – nur, wenn du die Regeltests lokal laufen lassen willst

## 1. Konten anlegen

- [ ] **Supabase**-Projekt, Region Frankfurt oder Zürich. Projekt-Ref und
      `anon key` notieren, `service_role key` gut wegpacken
- [ ] **OneSignal**-Account samt App. App-ID notieren
- [ ] **Firebase**-Projekt – wird von OneSignal für Android-Push gebraucht
      (Google verlangt das für FCM, unabhängig vom Push-Anbieter). Wird nur
      im OneSignal-Dashboard hinterlegt, taucht sonst nirgends im Code auf
- [ ] **Mailversand**: Resend, Postmark oder Mailgun. Kostenloses Kontingent
      reicht; du brauchst SMTP-Host, Port, Benutzer, Passwort
- [ ] **Webspeicher mit HTTPS** für die Web-App und die APK-Datei.
      Cloudflare Pages, Netlify oder Vercel, alle kostenlos.
      Ohne HTTPS gibt es kein Push

> Hinweis zum kostenlosen Supabase-Tarif: Projekte werden nach einer Woche ohne
> Zugriff schlafen gelegt. Solange jemand spielt, passiert das nicht. Legt die
> Runde eine längere Pause ein, musst du das Projekt im Dashboard wieder
> aufwecken – und die Zeitpläne für Erinnerungen laufen bis dahin nicht.

## 2. Wörterbuch bauen

- [ ] `de_DE.dic` und `de_DE.aff` von igerman98 nach `dict/sources/` legen
- [ ] Optional, aber empfohlen: Eigennamen-Liste aus einem Wiktionary-Dump als
      `dict/sources/propernouns.txt` (siehe `dict/README.md`)
- [ ] `cd dict && make`
- [ ] `make check` – muss bestehen
- [ ] Die ausgegebene Liste der zweibuchstabigen Wörter einmal durchsehen. Die
      entscheiden im Spiel überproportional viel
- [ ] `make install` (kopiert nach `app/assets/dict/`)

## 3. Datenbank aufsetzen

- [ ] `supabase link --project-ref <ref>`
- [ ] Im Dashboard unter *Database → Extensions* prüfen, dass `pg_net` und
      `pg_cron` verfügbar sind
- [ ] `supabase db push` – spielt alle sechs Migrationen ein
- [ ] `supabase test db` – die RLS-Tests müssen durchlaufen. **Nicht
      überspringen.** Ein Loch in der `racks`-Policy merkt man im Betrieb nicht,
      weil die App das gegnerische Rack ohnehin nicht anzeigt
- [ ] Storage-Bucket `dict` anlegen (privat) und die `.dawg` hochladen –
      im Dashboard oder mit
      `supabase storage cp dict/dist/de-2026.1.dawg ss:///dict/de-2026.1.dawg`
- [ ] Zwei Vault-Einträge anlegen, sonst verschickt der Server keine
      Benachrichtigungen:
      ```sql
      select vault.create_secret(
        'https://<ref>.supabase.co/functions/v1/send-push', 'push_function_url');
      select vault.create_secret('<service-role-key>', 'service_role_key');
      ```

## 4. Anmeldung einrichten

- [ ] *Authentication → Emails → SMTP Settings*: Zugangsdaten deines
      Mailversands eintragen. Der eingebaute Versand ist so stark gedrosselt,
      dass eure erste Registrierungsrunde hängenbleibt
- [ ] *Authentication → Providers → Email*: `Confirm email` eingeschaltet lassen
- [ ] *Authentication → URL Configuration*:
      - Site URL: `https://spelly.example.org`
      - Redirect URLs: `https://spelly.example.org/**` und
        `spelly://login-callback`

## 5. OneSignal einrichten

- [ ] Plattform-Ordner anlegen, damit die Android-Kennung feststeht:
      `cd app && flutter create --org de.spelly --project-name spelly --platforms=android,web .`
- [ ] Falls du die Kennung kürzen willst, jetzt in
      `android/app/build.gradle.kts` auf `de.spelly.app` ändern.
      **Danach nicht mehr anfassen** – sie entscheidet, ob eine neue Fassung
      sich über die installierte legt
- [ ] In `AndroidManifest.xml`: `android:label="Spelly"` setzen und den
      `intent-filter` für `spelly://login-callback` ergänzen
      (Wortlaut in `docs/distribution.md`)
- [ ] OneSignal-App → Plattform **Google Android (FCM)**: Firebase-Projekt
      mit genau dieser Android-Kennung anlegen, `google-services.json` nach
      `app/android/app/`; unter *Project Settings → Service accounts* einen
      privaten Schlüssel als JSON erzeugen und im OneSignal-Dashboard hochladen
- [ ] OneSignal-App → Plattform **Web Push** (Typical Web Push, Custom Code):
      Site-URL eintragen. OneSignal erzeugt VAPID-Schlüssel selbst, dafür ist
      keine Firebase-Web-App nötig
- [ ] *Settings → Keys & IDs*: **App-ID** und **REST API Key** notieren
- [ ] App-ID in `app/web/index.html` und `app/lib/main.dart`
      (`oneSignalAppId`) eintragen, falls sie sich geändert hat

## 6. Server-Geheimnisse setzen

```bash
supabase secrets set \
  ONESIGNAL_APP_ID=<app-id> \
  ONESIGNAL_REST_API_KEY=<rest-api-key> \
  DICT_VERSION=de-2026.1
```

- [ ] gesetzt

## 7. Edge Functions ausrollen

```bash
supabase functions deploy submit-move
supabase functions deploy create-game
supabase functions deploy send-push
```

- [ ] alle drei durch

## 8. Symbole und Prüfläufe

- [ ] App-Symbole erzeugen: `app/web/icons/Icon-192.png`, `Icon-512.png`,
      `Icon-maskable-192.png`, `Icon-maskable-512.png`, `app/web/favicon.png`
      sowie die Android-Symbole unter `android/app/src/main/res/`
- [ ] `cd app && flutter pub get`
- [ ] `flutter analyze` – der Dart-Code ist bisher nicht kompiliert worden,
      hier fallen Tippfehler auf
- [ ] `flutter test` – prüft die Regeln gegen `shared/rules-cases.json`

## 9. Web-App ausliefern

```bash
cd app
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=AUTH_REDIRECT=https://spelly.example.org
```

- [ ] `build/web/` auf den Webspeicher, HTTPS aktiv
- [ ] Auf einem echten iPhone testen: Safari, Teilen, Zum Home-Bildschirm,
      über das Symbol starten, registrieren, Benachrichtigung kommt an

## 10. APK bauen

- [ ] Signierschlüssel anlegen und sichern:
      `keytool -genkey -v -keystore ~/spelly.jks -keyalg RSA -keysize 2048 -validity 10000 -alias spelly`
- [ ] `app/android/key.properties` anlegen (steht in `.gitignore`)
- [ ] Signierung in `android/app/build.gradle.kts` eintragen
- [ ] ```bash
      flutter build apk --release \
        --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
        --dart-define=SUPABASE_ANON_KEY=<anon-key> \
        --dart-define=AUTH_REDIRECT=spelly://login-callback
      ```
- [ ] `app-release.apk` auf den Webspeicher
- [ ] Auf einem echten Android-Gerät installieren und durchspielen

## 11. Versionsstand hinterlegen

```sql
insert into app_release (platform, version, download_url)
values ('android', '0.1.0', 'https://spelly.example.org/app-release.apk'),
       ('web', '0.1.0', 'https://spelly.example.org')
on conflict (platform) do update
set version = excluded.version,
    download_url = excluded.download_url,
    updated_at = now();
```

## 12. Verschicken

- [ ] In `docs/anleitung-android.md` und `docs/anleitung-ios.md` die
      Platzhalter durch die echten Links ersetzen
- [ ] Zwei eigene Konten anlegen und eine Partie komplett durchspielen –
      Herausforderung, Annahme, mehrere Züge, Benachrichtigungen auf beiden
      Geräten, Partieende
- [ ] Erst dann die Links an die Runde geben

---

## Was im Code noch fehlt

Damit du nicht mitten im Aufsetzen darüber stolperst – das ist bewusst offen und
blockiert den ersten Versand nicht:

| Lücke | Auswirkung |
|---|---|
| Passwort-Zurücksetzen | Die Mail geht raus, aber es fehlt der Bildschirm zum Eingeben des neuen Passworts. Bis dahin setzt du Passwörter im Dashboard zurück |
| Versionsprüfung im Client | `app_release` ist angelegt und wird gelesen, aber noch nicht angezeigt. Bis dahin sagst du selbst Bescheid, wenn ein neues APK da ist |
| Bildschirm zum Partieende | Die Schlussabrechnung läuft serverseitig korrekt, es fehlt die Anzeige. Momentan steht nur „Beendet" mit dem Endstand |
| Steine tauschen | Server und Repository können es, es gibt keinen Knopf |
| Wort melden | Dito. Ohne den Knopf schärfst du die Wortliste blind nach |
| Mehrsprachigkeit | `l10n/` ist leer, alle Texte stehen deutsch im Code |
