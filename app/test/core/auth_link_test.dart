import 'package:flutter_test/flutter_test.dart';
import 'package:spelly/core/auth_link.dart';

void main() {
  group('Link aus der Mail', () {
    test('saubere Adresse meldet nichts', () {
      expect(linkProblem(Uri.parse('https://olgo.github.io/spelly/')), isNull);
    });

    test('abgelaufener Link nennt den Ablauf', () {
      final message = linkProblem(Uri.parse(
        'https://olgo.github.io/spelly/?error=access_denied'
        '&error_code=otp_expired&error_description=Email+link+has+expired',
      ));
      expect(message, contains('abgelaufen'));
    });

    test('anderer Fehlercode bekommt trotzdem einen Satz', () {
      final message = linkProblem(
        Uri.parse('https://olgo.github.io/spelly/?error_code=validation_failed'),
      );
      expect(message, isNotNull);
      expect(message, isNot(contains('abgelaufen')));
    });

    // Der wichtigste Fall: Der Code steht noch in der Adresse, also hat
    // supabase_flutter nicht aufgeräumt – das tut es nur nach einem geglückten
    // Tausch. Aufgerufen wird das nur ohne Sitzung, es kann also nicht der
    // Nachklang eines erfolgreichen Einlösens sein.
    test('nicht eingelöster Code weist auf das falsche Gerät hin', () {
      final message = linkProblem(
        Uri.parse('https://olgo.github.io/spelly/?code=abc123'),
      );
      expect(message, contains('Gerät'));
    });

    test('ein Fehlercode geht dem Code vor', () {
      final message = linkProblem(Uri.parse(
        'https://olgo.github.io/spelly/?code=abc123&error_code=otp_expired',
      ));
      expect(message, contains('abgelaufen'));
    });

    test('auf dem Telefon ist Uri.base ein Pfad ohne Parameter', () {
      expect(linkProblem(Uri.parse('file:///data/user/0/de.spelly/')), isNull);
    });
  });
}
