# Verteilung ohne Store

Zwei Wege, ein Code: Android bekommt ein APK zum Herunterladen, iOS bekommt
dieselbe App als Web-App zum Ablegen auf dem Home-Bildschirm.

## Einmalige Einrichtung

### Plattform-Ordner anlegen

Das Repo enthält nur `lib/`, `test/`, `web/` und `assets/`. Die von Flutter
erzeugten Ordner `android/` und `ios/` fehlen absichtlich – sie sind
Generat. Einmal anlegen:

```bash
cd app
flutter create --org de.spelly --project-name spelly --platforms=android,web .
```

Das setzt die Android-Kennung auf `de.spelly.spelly`. Wenn du es kürzer magst,
danach in `android/app/build.gradle.kts` von Hand ändern:

```kotlin
applicationId = "de.spelly.app"
```

**Diese Kennung entscheidet, ob eine Aktualisierung sich über die installierte
App legt oder als zweite App daneben landet.** Sie muss also stehen, bevor das
erste APK verschickt wird, und danach unangetastet bleiben. Sie muss ausserdem
genau so in Firebase registriert sein.

`flutter create` überschreibt `web/index.html` und `web/manifest.json` nicht,
wenn sie schon da sind – die im Repo enthaltenen Fassungen bleiben also erhalten.
Prüf es trotzdem einmal nach: dort stehen der Name auf dem Home-Bildschirm und
die Einstellungen, die die Web-App ohne Browserleiste starten lassen.

### Anmeldung aus der Mail zurück in die App

Damit der Link in der Bestätigungsmail die Android-App öffnet und nicht nur den
Browser, braucht `android/app/src/main/AndroidManifest.xml` innerhalb der
`<activity android:name=".MainActivity">` einen zusätzlichen Eintrag:

```xml
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data android:scheme="spelly" android:host="login-callback" />
</intent-filter>
```

Der angezeigte Name der App steht in derselben Datei als `android:label` im
`<application>`-Tag – dort `Spelly` eintragen.

### Supabase: Bestätigungsmail

Der eingebaute Mailversand ist stark gedrosselt und taugt nicht für echte
Registrierungen. Trag einen eigenen SMTP-Dienst ein (Resend, Postmark,
Mailgun – die kostenlosen Kontingente reichen für einen Freundeskreis weit):

*Authentication → Emails → SMTP Settings*, dann in *URL Configuration*:

```
Site URL:        https://spelly.example.org
Redirect URLs:   https://spelly.example.org/**
                 spelly://login-callback
```

Die zweite Adresse ist das URL-Schema der Android-App. Ohne sie landet der
Klick in der Bestätigungsmail im Browser statt in der App.

`Confirm email` bleibt eingeschaltet.

### Firebase

Ein Projekt, darin zwei Apps: eine Android-App und eine Web-App.

* Android: `google-services.json` nach `app/android/app/`
* Web: Konfigurationswerte in `app/web/firebase-messaging-sw.js` eintragen
* Web-Push-Zertifikat erzeugen (*Project Settings → Cloud Messaging → Web
  Push certificates*), den Schlüssel als `FCM_VAPID_KEY` an den Build geben
* `flutterfire configure` erzeugt `app/lib/firebase_options.dart`

## Android: APK

Einmalig einen Signierschlüssel anlegen. Nicht verlieren – ohne ihn kannst du
später keine Aktualisierung ausliefern, die sich über die alte installiert:

```bash
keytool -genkey -v -keystore ~/spelly.jks -keyalg RSA \
        -keysize 2048 -validity 10000 -alias spelly
```

`app/android/key.properties` (steht in `.gitignore`):

```properties
storePassword=…
keyPassword=…
keyAlias=spelly
storeFile=/absoluter/pfad/spelly.jks
```

Bauen:

```bash
cd app
flutter build apk --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=AUTH_REDIRECT=spelly://login-callback
```

Ergebnis: `build/app/outputs/flutter-apk/app-release.apk`. Irgendwo ablegen,
wo deine Leute drankommen, und den Link verschicken.

Beim ersten Mal muss auf dem Telefon die Installation aus dieser Quelle erlaubt
werden – Android fragt von selbst und führt in die richtige Einstellung.

## iOS und alle anderen: Web-App

```bash
cd app
flutter build web --release \
  --dart-define=SUPABASE_URL=https://<ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<anon-key> \
  --dart-define=FCM_VAPID_KEY=<vapid-key> \
  --dart-define=AUTH_REDIRECT=https://spelly.example.org
```

`build/web/` auf einen beliebigen Webspeicher legen. Zwei Bedingungen:

* **HTTPS ist Pflicht.** Ohne gibt es keinen Service Worker und damit kein Push.
* Kein Unterverzeichnis, oder `--base-href` entsprechend setzen.

Anleitung für die iPhone-Runde, am besten mit dem Link mitschicken:

> Link in **Safari** öffnen (nicht Chrome), Teilen-Symbol antippen,
> **Zum Home-Bildschirm**. Danach die App über das neue Symbol starten –
> nur so kommen die Benachrichtigungen an.

Das ist die entscheidende Einschränkung dieser Variante: Web-Push funktioniert
auf iOS ausschliesslich bei zum Home-Bildschirm hinzugefügten Web-Apps. Wer den
Link nur im Browser offen lässt, erfährt nie, dass er am Zug ist.

## Aktualisierungen

Die Web-App aktualisiert sich beim nächsten Start von selbst. Das APK nicht –
deshalb gibt es die Tabelle `app_release`:

```sql
insert into app_release (platform, version, download_url, notes)
values ('android', '0.2.0', 'https://…/app-release.apk', 'Einladungen')
on conflict (platform) do update
set version = excluded.version,
    download_url = excluded.download_url,
    notes = excluded.notes,
    updated_at = now();
```

Der Client vergleicht beim Start seine eigene Version damit und weist auf einen
neuen Stand hin. `mandatory = true` setzen, wenn eine Änderung am Server alte
Stände unbrauchbar macht – etwa eine neue Wörterbuchversion.

## Wörterbuch

Die gebaute Wortliste muss an zwei Stellen liegen:

```bash
cd dict && make install                      # nach app/assets/dict/
supabase storage cp dist/de-2026.1.dawg ss:///dict/de-2026.1.dawg
```

Die Web-App lädt die Datei beim ersten Start über das Netz – rund fünf
Megabyte, danach liegt sie im Cache des Service Workers.
