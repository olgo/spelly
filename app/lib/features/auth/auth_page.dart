import 'package:flutter/material.dart';

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
        // Ohne Mailversand ist die Anmeldung sofort aktiv - der AuthGate in
        // main.dart schaltet von selbst zur Lobby weiter.
      } else {
        await widget.auth.signIn(
          email: _email.text,
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

                    _Field(
                      controller: _email,
                      label: 'E-Mail',
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      textInputAction: TextInputAction.next,
                      validator: (v) {
                        final value = v?.trim() ?? '';
                        if (!value.contains('@') || !value.contains('.')) {
                          return 'Das sieht nicht nach einer Adresse aus.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

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
          'E-Mail oder Passwort stimmt nicht.',
        AuthProblem.emailNotConfirmed =>
          'Die Adresse ist noch nicht bestätigt.',
        AuthProblem.emailTaken =>
          'Mit dieser Adresse gibt es schon ein Konto. Melde dich an.',
        AuthProblem.weakPassword => 'Das Passwort ist zu kurz.',
        AuthProblem.invalidEmail => 'Die Adresse stimmt so nicht.',
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
