import 'package:onesignal_flutter/onesignal_flutter.dart';

/// Die native Seite der Brücke – siehe `onesignal_bridge.dart`. Hier ist alles
/// nur Durchreiche ans Flutter-Paket.
abstract final class OneSignalApi {
  /// Auf Android und iOS gibt es Push immer. Die Frage stellt sich nur im
  /// Browser, wo Safari sie ausserhalb der Home-Bildschirm-App verneint.
  static bool get isSupported => true;

  static bool get hasPermission => OneSignal.Notifications.permission;

  static Future<void> initialize(String appId) => OneSignal.initialize(appId);

  static Future<void> login(String externalId) => OneSignal.login(externalId);

  static Future<void> logout() => OneSignal.logout();

  /// `true`: Wer schon einmal abgelehnt hat, wird zu den Einstellungen
  /// geschickt, statt einen Dialog zu bekommen, den das System nicht mehr
  /// zeigt.
  static Future<bool> requestPermission() =>
      OneSignal.Notifications.requestPermission(true);

  static void onClick(void Function(Map<String, dynamic>? data) handler) {
    OneSignal.Notifications.addClickListener(
      (event) => handler(event.notification.additionalData),
    );
  }
}
