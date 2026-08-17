import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth_repository.dart';
import 'auth_page.dart';

/// Der Abschluss von „Passwort vergessen".
///
/// Der Klick in der Wiederherstellungsmail meldet an – mehr nicht. Ohne diesen
/// Bildschirm landete man direkt in der Lobby, und das alte, vergessene
/// Passwort stünde weiterhin. Beim nächsten Anmelden ginge dasselbe von vorn
/// los, endlos.
///
/// Deshalb kein „Später": Wer hier ankommt, ist über einen Link hereingekommen
/// und hat gerade kein Passwort, das er kennt. Der einzige Ausweg ohne neues
/// Passwort ist das Abmelden – wer das tut, steht wieder vor der Anmeldung und
/// kann eine neue Mail anfordern.
class NewPasswordPage extends StatefulWidget {
  const NewPasswordPage({
    super.key,
    required this.auth,
    required this.onDone,
  });

  final AuthRepository auth;
  final VoidCallback onDone;

  @override
  State<NewPasswordPage> createState() => _NewPasswordPageState();
}

class _NewPasswordPageState extends State<NewPasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await widget.auth.updatePassword(_password.text);
      if (mounted) widget.onDone();
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = authMessage(failure.problem));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Das hat nicht geklappt. Versuch es nochmal.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Die Zurück-Geste darf hier nicht vorbeiführen: Dahinter läge die Lobby
    // mit einer gültigen Sitzung, aber unverändertem Passwort.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Neues Passwort',
                        style: TextStyle(
                          color: Palette.text,
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Du bist über den Link aus der Mail hier. Setz jetzt '
                        'ein neues Passwort – danach geht es weiter zur Lobby.',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      const SizedBox(height: 22),

                      AuthField(
                        controller: _password,
                        label: 'Neues Passwort',
                        obscure: true,
                        autofillHints: const [AutofillHints.newPassword],
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null ||
                                v.length < minPasswordLength)
                            ? 'Mindestens acht Zeichen.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      AuthField(
                        controller: _repeat,
                        label: 'Passwort wiederholen',
                        obscure: true,
                        textInputAction: TextInputAction.done,
                        validator: (v) => v == _password.text
                            ? null
                            : 'Die beiden Eingaben stimmen nicht überein.',
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Palette.warn,
                            fontSize: 13,
                            height: 1.3,
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Palette.signal,
                          foregroundColor: Palette.boneInk,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: _busy ? null : _save,
                        child: Text(_busy ? 'Moment' : 'Passwort speichern'),
                      ),
                      const SizedBox(height: 6),
                      TextButton(
                        onPressed: _busy ? null : widget.auth.signOut,
                        child: const Text('Abbrechen und abmelden'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
