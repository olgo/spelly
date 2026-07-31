import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Legt das Sitzungstoken in der Keychain (iOS) bzw. im Keystore (Android) ab.
///
/// Der Standard von supabase_flutter benutzt SharedPreferences – das ist eine
/// unverschlüsselte Datei. Auf einem entsperrten Gerät ist der Unterschied
/// akademisch, auf einem gestohlenen nicht.
///
/// Im Browser gibt es nichts Vergleichbares; dort bleibt es beim Standard.
class SecureSessionStorage extends LocalStorage {
  const SecureSessionStorage();

  static const _key = 'supabase.session';
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  @override
  Future<void> initialize() async {}

  @override
  Future<String?> accessToken() => _storage.read(key: _key);

  @override
  Future<bool> hasAccessToken() async =>
      await _storage.read(key: _key) != null;

  @override
  Future<void> persistSession(String persistSessionString) =>
      _storage.write(key: _key, value: persistSessionString);

  @override
  Future<void> removePersistedSession() => _storage.delete(key: _key);
}

/// Der Standardspeicher fürs Web, der sichere für die Telefone.
LocalStorage sessionStorage() => kIsWeb
    ? SharedPreferencesLocalStorage(persistSessionKey: 'supabase.session')
    : const SecureSessionStorage();
