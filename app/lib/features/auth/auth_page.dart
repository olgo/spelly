import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../data/auth_repository.dart';

enum _Mode { signIn, signUp }

/// Bewusst grob: Hier soll nur der Tippfehler hängenbleiben, der sonst als
/// unverständlicher Serverfehler zurückkäme. Ob es die Adresse gibt, weiss
/// ohnehin erst das Postfach.
bool looksLikeEmail(String value) {
  final trimmed = value.trim();
  return trimmed.contains('@') && trimmed.contains('.');
}

/// Mindestlänge für ein neues Passwort. Steht hier, weil sowohl die
/// Registrierung als auch das Zurücksetzen dieselbe Zusage machen müssen.
const minPasswordLength = 8;

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth, this.initialError});
  final AuthRepository auth;

  /// Etwas, das schon vor dem ersten Tippen schiefging – etwa ein abgelaufener
  /// Link aus einer Mail. Ohne diesen Weg stünde man vor der Maske und wüsste
  /// nicht, warum der Klick nichts bewirkt hat.
  final String? initialError;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();
  final _code = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  String? _notice;

  /// Die Adresse, an die der Code ging. Festgehalten statt beim Einlösen neu
  /// aus dem Feld gelesen: Wer zwischendurch etwas anderes eintippt, bekäme
  /// sonst einen Fehler, der nach einem falschen Code aussieht.
  String? _codeSentTo;

  @override
  void initState() {
    super.initState();
    _error = widget.initialError;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    _code.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == _Mode.signUp;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_isSignUp) {
        await widget.auth.signUp(
          email: _email.text,
          password: _password.text,
          displayName: _name.text,
        );
        setState(() {
          _notice = 'Wir haben dir eine Mail geschickt. Bestätige die Adresse, '
              'dann kannst du dich anmelden.';
          _mode = _Mode.signIn;
          _password.clear();
          _repeat.clear();
        });
      } else {
        await widget.auth.signIn(
          email: _email.text,
          password: _password.text,
        );
        // Der AuthGate in main.dart schaltet von selbst weiter.
      }
    } on AuthFailure catch (failure) {
      setState(() => _error = authMessage(failure.problem));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Gemeinsamer Ablauf für die beiden Mail-Knöpfe.
  ///
  /// Beide liefen früher ohne Absicherung: Warf der Aufruf – und der
  /// wahrscheinlichste Fall ist die Drosselung, wenn jemand zweimal tippt –,
  /// wurde die Meldung nie gesetzt und der Fehler landete nur in der Konsole.
  /// Auf dem Bildschirm passierte gar nichts.
  Future<bool> _sendMail(
    Future<void> Function(String email) send,
    String success,
  ) async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Trag zuerst deine Adresse ein.');
      return false;
    }
    if (!looksLikeEmail(email)) {
      setState(() => _error = 'Das sieht nicht nach einer Adresse aus.');
      return false;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await send(email);
      if (mounted) setState(() => _notice = success);
      return true;
    } on AuthFailure catch (failure) {
      if (mounted) setState(() => _error = authMessage(failure.problem));
      return false;
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Das hat nicht geklappt. Versuch es nochmal.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resend() => _sendMail(
        widget.auth.resendConfirmation,
        'Bestätigungsmail ist noch einmal unterwegs.',
      );

  Future<void> _reset() async {
    final sent = await _sendMail(
      widget.auth.sendPasswordReset,
      'Wenn es das Konto gibt, ist eine Mail mit einem sechsstelligen Code '
          'unterwegs. Trag ihn unten ein.',
    );
    if (sent && mounted) {
      setState(() {
        _codeSentTo = _email.text.trim();
        _code.clear();
      });
    }
  }

  /// Löst den Code ein. Danach übernimmt der AuthGate: Das
  /// `passwordRecovery`-Ereignis führt auf den Bildschirm für das neue
  /// Passwort, hier ist nichts weiter zu tun.
  Future<void> _verifyCode() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = 'Der Code hat sechs Ziffern.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      await widget.auth.verifyRecoveryCode(email: _codeSentTo!, code: code);
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
    return Scaffold(
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
                    Text(
                      _isSignUp ? 'Konto anlegen' : 'Anmelden',
                      style: const TextStyle(
                        color: Palette.text,
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSignUp
                          ? 'Der Anzeigename steht später in der Spielerliste.'
                          : 'Du bleibst angemeldet, bis du dich abmeldest.',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                    const SizedBox(height: 22),

                    if (_isSignUp) ...[
                      AuthField(
                        controller: _name,
                        label: 'Anzeigename',
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Mindestens zwei Zeichen.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],

                    AuthField(
                      controller: _email,
                      label: 'E-Mail',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (v) => looksLikeEmail(v ?? '')
                          ? null
                          : 'Das sieht nicht nach einer Adresse aus.',
                    ),
                    const SizedBox(height: 12),

                    AuthField(
                      controller: _password,
                      label: 'Passwort',
                      obscure: true,
                      autofillHints: [
                        _isSignUp
                            ? AutofillHints.newPassword
                            : AutofillHints.password,
                      ],
                      textInputAction: _isSignUp
                          ? TextInputAction.next
                          : TextInputAction.done,
                      validator: (v) {
                        if (!_isSignUp) {
                          return (v == null || v.isEmpty)
                              ? 'Passwort fehlt.'
                              : null;
                        }
                        if (v == null || v.length < minPasswordLength) {
                          return 'Mindestens acht Zeichen.';
                        }
                        return null;
                      },
                    ),

                    if (_isSignUp) ...[
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
                    ],

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
                    if (_notice != null) ...[
                      const SizedBox(height: 14),
                      Text(
                        _notice!,
                        style: const TextStyle(
                          color: Palette.signal,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                    ],

                    // Erscheint erst, wenn die Mail draussen ist. Kein Link
                    // zum Klicken: iOS öffnet Links immer im Standardbrowser,
                    // nie in der App vom Home-Bildschirm – der Code dagegen
                    // wird da eingetippt, wo man ohnehin schon steht.
                    if (_codeSentTo != null) ...[
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: AuthField(
                              controller: _code,
                              label: 'Code aus der Mail',
                              keyboardType: TextInputType.number,
                              autofillHints: const [AutofillHints.oneTimeCode],
                              textInputAction: TextInputAction.done,
                              // Bewusst ohne Prüfung: Das Formular wird auch
                              // vom Anmelde-Knopf geprüft, und dort darf ein
                              // leeres Code-Feld nicht im Weg stehen.
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Palette.signal,
                              foregroundColor: Palette.boneInk,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 18,
                              ),
                            ),
                            onPressed: _busy ? null : _verifyCode,
                            child: const Text('Weiter'),
                          ),
                        ],
                      ),
                    ],

                    const SizedBox(height: 20),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: Palette.signal,
                        foregroundColor: Palette.boneInk,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        _busy
                            ? 'Moment'
                            : _isSignUp
                                ? 'Konto anlegen'
                                : 'Anmelden',
                      ),
                    ),

                    const SizedBox(height: 6),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _mode = _isSignUp ? _Mode.signIn : _Mode.signUp;
                                _error = null;
                                _notice = null;
                                // Wer die Seite wechselt, ist mit dem
                                // Zurücksetzen durch – das Feld hat dort
                                // nichts mehr zu suchen.
                                _codeSentTo = null;
                              }),
                      child: Text(
                        _isSignUp
                            ? 'Ich habe schon ein Konto'
                            : 'Neu hier? Konto anlegen',
                      ),
                    ),

                    if (!_isSignUp)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          TextButton(
                            onPressed: _busy ? null : _resend,
                            child: const Text('Mail nochmal senden'),
                          ),
                          TextButton(
                            onPressed: _busy ? null : _reset,
                            child: const Text('Passwort vergessen'),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Die Texte zu den Anmelde-Problemen. Öffentlich, weil der Bildschirm zum
/// Setzen eines neuen Passworts dieselben Fälle abbekommt.
String authMessage(AuthProblem problem) => switch (problem) {
        AuthProblem.invalidCredentials =>
          'E-Mail oder Passwort stimmt nicht.',
        AuthProblem.emailNotConfirmed =>
          'Die Adresse ist noch nicht bestätigt. Schau in dein Postfach – '
              'oder lass dir die Mail nochmal schicken.',
        AuthProblem.emailTaken =>
          'Mit dieser Adresse gibt es schon ein Konto. Melde dich an.',
        AuthProblem.weakPassword => 'Das Passwort ist zu kurz.',
        AuthProblem.samePassword =>
          'Das ist dein bisheriges Passwort. Denk dir ein anderes aus.',
        AuthProblem.invalidCode =>
          'Der Code stimmt nicht oder ist abgelaufen. Fordere unten einen '
              'neuen an.',
        AuthProblem.invalidEmail => 'Die Adresse stimmt so nicht.',
        AuthProblem.rateLimited =>
          'Zu viele Versuche. Warte ein paar Minuten.',
        AuthProblem.unknown => 'Das hat nicht geklappt. Versuch es nochmal.',
      };

class AuthField extends StatelessWidget {
  const AuthField({
    required this.controller,
    required this.label,
    this.obscure = false,
    this.keyboardType,
    this.autofillHints,
    this.textInputAction,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final bool obscure;
  final TextInputType? keyboardType;
  final List<String>? autofillHints;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      textInputAction: textInputAction,
      validator: validator,
      style: const TextStyle(color: Palette.text),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Palette.textDim),
        filled: true,
        fillColor: Palette.boardInk,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Palette.hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Palette.signal),
        ),
      ),
    );
  }
}
