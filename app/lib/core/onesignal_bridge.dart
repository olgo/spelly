/// Zugang zu OneSignal, für beide Welten dieselbe Handvoll Aufrufe.
///
/// Nötig, weil `onesignal_flutter` **kein Web unterstützt**: Die `pubspec.yaml`
/// des Pakets nennt nur `android` und `ios`. Im Browser lief deshalb jeder
/// Aufruf in eine `MissingPluginException` – die Kennung wurde nie gesetzt,
/// der Versand traf null Empfänger, und die Warteschlange verbuchte das
/// klaglos als `no_recipient`. Im Web gibt es stattdessen das JS-SDK, das
/// `web/index.html` ohnehin schon lädt; hier wird es nur angerufen.
///
/// Der bedingte Export wählt die passende Seite: Der spätere Android-Build
/// benutzt weiterhin das Flutter-Paket, der Web-Build das JS-SDK.
export 'onesignal_bridge_native.dart'
    if (dart.library.js_interop) 'onesignal_bridge_web.dart';
