/// Warum der Link aus einer Mail nicht funktioniert hat.
///
/// Ausgewertet wird die Adresszeile, und das trägt nur, weil supabase_flutter
/// sie **ausschliesslich nach einem geglückten Einlösen** aufräumt
/// (`clearAuthUrlParameters`, aufgerufen im `try` von `_handleDeeplink`).
/// Steht dort noch etwas, ist etwas schiefgegangen. Gemeldet wird das sonst
/// nirgends: Der Fehler landet im Protokoll, und man stünde ratlos vor der
/// Anmeldemaske.
///
/// Nur aufrufen, wenn keine Sitzung besteht – „Code da, aber nicht angemeldet"
/// ist genau die Auskunft, aus der [linkProblem] seinen zweiten Fall zieht.
///
/// Auf Android und iOS ist `Uri.base` ein Dateipfad ohne Parameter, dort
/// liefert das immer `null`.
String? linkProblem(Uri url) {
  final params = url.queryParameters;

  final failure = params['error_code'];
  if (failure != null) {
    return failure == 'otp_expired'
        ? 'Der Link aus der Mail ist abgelaufen. Fordere unten einen neuen an.'
        : 'Der Link aus der Mail hat nicht funktioniert. Fordere unten einen '
            'neuen an.';
  }

  // Der Prüfschlüssel zum Code liegt im Speicher genau des Browsers, der die
  // Mail angefordert hat. Auf dem iPhone ist das der häufigste Stolperstein:
  // getippt in der App vom Home-Bildschirm, geöffnet in Safari – zwei
  // getrennte Speicher, und der Tausch scheitert.
  if (params['code'] != null) {
    return 'Der Link liess sich hier nicht einlösen. Öffne ihn dort, wo du '
        '„Passwort vergessen" getippt hast – oder fordere unten eine neue '
        'Mail an und klick den Link auf demselben Gerät.';
  }

  return null;
}
