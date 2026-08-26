import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Die native Seite der Brücke – siehe `onesignal_bridge.dart`. Hier ist alles
/// nur Durchreiche ans Flutter-Paket.
abstract final class OneSignalApi {
  /// Auf Android und iOS gibt es Push immer. Die Frage stellt sich nur im
  /// Browser, wo Safari sie ausserhalb der Home-Bildschirm-App verneint.
  static bool get isSupported => true;

  static bool get hasPermission => OneSignal.Notifications.permission;

  /// Ob OneSignal dieses Gerät wirklich als Empfänger führt. Geprüft wird
  /// die Subscription-`id`, nicht `optedIn` – siehe die Web-Fassung dieser
  /// Brücke für den Hintergrund (dasselbe `optedIn`-Missverständnis gilt
  /// laut SDK-Dokumentation auch nativ).
  static Future<bool> isSubscribed() async =>
      OneSignal.User.pushSubscription.id != null;

  static Future<void> initialize(String appId) => OneSignal.initialize(appId);

  static Future<void> login(String externalId) => OneSignal.login(externalId);

  static Future<void> logout() => OneSignal.logout();

  /// `true`: Wer schon einmal abgelehnt hat, wird zu den Einstellungen
  /// geschickt, statt einen Dialog zu bekommen, den das System nicht mehr
  /// zeigt.
  static Future<PushEnableResult> requestPermission() async {
    final granted = await OneSignal.Notifications.requestPermission(true);
    return PushEnableResult(
      granted ? PushEnableOutcome.granted : PushEnableOutcome.browserDenied,
    );
  }

  static void onClick(void Function(Map<String, dynamic>? data) handler) {
    OneSignal.Notifications.addClickListener(
      (event) => handler(event.notification.additionalData),
    );
  }
}

/// Siehe die Web-Fassung dieser Brücke – derselbe Typ, unabhängig definiert,
/// weil `onesignal_bridge.dart` nur eine der beiden Dateien durchreicht.
enum PushEnableOutcome {
  granted,
  unsupported,
  browserDenied,
  sdkUnavailable,
  subscriptionFailed,
}

class PushEnableResult {
  const PushEnableResult(this.outcome, [this.detail]);
  final PushEnableOutcome outcome;
  final String? detail;
  bool get granted => outcome == PushEnableOutcome.granted;
}
