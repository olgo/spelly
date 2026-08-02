import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme.dart';
import '../../data/auth_repository.dart';

enum _Mode { signIn, signUp }

class AuthPage extends StatefulWidget {
  const AuthPage({super.key, required this.auth});
  final AuthRepository auth;

  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _repeat = TextEditingController();

  _Mode _mode = _Mode.signIn;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _repeat.dispose();
    super.dispose();
  }

  bool get _isSignUp => _mode == _Mode.signUp;

  /// Ohne Mailversand dient die E-Mail nur noch als technische Kontokennung
  /// für Supabase, nicht als erreichbare Adresse. Beim Anlegen erfindet die
  /// App deshalb selbst eine zufällige – der Nutzer sieht sie einmal als
  /// Wiederherstellungscode (siehe [_showRecoveryCode]).
  String _generateRecoveryEmail() {
    const chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final token =
        List.generate(16, (_) => chars[random.nextInt(chars.length)]).join();
    return '$token@spelly.local';
  }

  /// Zeigt die erfundene Adresse einmalig an. Ohne sie zu notieren, kommt
  /// niemand mehr ins Konto zurück, sobald die laufende Sitzung endet – es
  /// gibt ja keinen Mailversand für ein "Passwort vergessen".
  Future<bool> _showRecoveryCode(String email) async {
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: Palette.boardInk,
        title: const Text('Dein Wiederherstellungscode'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Notier dir diese Adresse. Du brauchst sie, um dich nach dem '
              'Abmelden oder auf einem anderen Gerät wieder anzumelden – '
              'ohne sie kommst du nicht mehr an dein Konto.',
            ),
            const SizedBox(height: 14),
            SelectableText(
              email,
              style: const TextStyle(
                color: Palette.signal,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: email)),
            child: const Text('Kopieren'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Notiert, weiter'),
          ),
        ],
      ),
    );
    return proceed ?? false;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    String email;
    if (_isSignUp) {
      email = _generateRecoveryEmail();
      if (!await _showRecoveryCode(email)) return;
    } else {
      email = _email.text;
    }

    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });

    try {
      if (_isSignUp) {
        await widget.auth.signUp(
          email: email,
          password: _password.text,
          displayName: _name.text,
        );
        // Ohne Mailversand ist die Anmeldung sofort aktiv - der AuthGate in
        // main.dart schaltet von selbst zur Lobby weiter.
      } else {
        await widget.auth.signIn(
          email: email,
          password: _password.text,
        );
        // Der AuthGate in main.dart schaltet von selbst weiter.
      }
    } on AuthFailure catch (failure) {
      setState(() => _error = _message(failure.problem));
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
                      _Field(
                        controller: _name,
                        label: 'Anzeigename',
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().length < 2)
                            ? 'Mindestens zwei Zeichen.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (!_isSignUp) ...[
                      _Field(
                        controller: _email,
                        label: 'Wiederherstellungscode',
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (!value.contains('@') || !value.contains('.')) {
                            return 'Das sieht nicht nach deinem '
                                'Wiederherstellungscode aus.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                    ],

                    _Field(
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
                        if (v == null || v.length < 8) {
                          return 'Mindestens acht Zeichen.';
                        }
                        return null;
                      },
                    ),

                    if (_isSignUp) ...[
                      const SizedBox(height: 12),
                      _Field(
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
                              }),
                      child: Text(
                        _isSignUp
                            ? 'Ich habe schon ein Konto'
                            : 'Neu hier? Konto anlegen',
                      ),
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

  String _message(AuthProblem problem) => switch (problem) {
        AuthProblem.invalidCredentials =>
          'Wiederherstellungscode oder Passwort stimmt nicht.',
        AuthProblem.emailNotConfirmed =>
          'Die Adresse ist noch nicht bestätigt.',
        AuthProblem.emailTaken =>
          // Kann beim Anlegen nur durch eine Zufallskollision im
          // generierten Wiederherstellungscode passieren - einfach nochmal
          // versuchen, dann wird ein neuer erfunden.
          'Das hat aus einem technischen Grund nicht geklappt. '
              'Versuch es einfach nochmal.',
        AuthProblem.weakPassword => 'Das Passwort ist zu kurz.',
        AuthProblem.invalidEmail =>
          'Der Wiederherstellungscode stimmt so nicht.',
        AuthProblem.rateLimited =>
          'Zu viele Versuche. Warte ein paar Minuten.',
        AuthProblem.unknown => 'Das hat nicht geklappt. Versuch es nochmal.',
      };
}

class _Field extends StatelessWidget {
  const _Field({
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
