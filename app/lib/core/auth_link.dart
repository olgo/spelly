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

  // Bleibt nur noch die Bestätigungsmail übrig – „Passwort vergessen" läuft
  // inzwischen über einen Code und ohne Link, eben weil dieser Fall auf dem
  // iPhone unvermeidlich ist: Der PKCE-Prüfschlüssel liegt im Speicher des
  // Browsers, der die Mail angefordert hat, und iOS öffnet Links immer im
  // Standardbrowser.
  //
  // Halb so wild: Bestätigt wird die Adresse schon auf dem Server, bevor der
  // Rücksprung überhaupt losgeht. Gescheitert ist nur das automatische
  // Anmelden – und das ist kein Verlust, das Passwort kennt man ja.
  if (params['code'] != null) {
    return 'Deine Adresse ist bestätigt, nur das automatische Anmelden hat '
        'hier nicht geklappt. Melde dich einfach mit E-Mail und Passwort an.';
  }

  return null;
}
