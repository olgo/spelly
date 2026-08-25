import 'dart:async';
import 'dart:js_interop';

/// Die Web-Seite der Brücke – siehe `onesignal_bridge.dart`. Spricht das
/// JS-SDK an, das `web/index.html` lädt und einrichtet.
abstract final class OneSignalApi {
  /// Ob der Browser überhaupt Push kann. Bewusst am Browser gefragt und nicht
  /// am SDK: Die Antwort wird beim ersten Aufbau der Lobby gebraucht, das SDK
  /// ist da womöglich noch nicht geladen.
  ///
  /// Auf dem iPhone ist das die entscheidende Unterscheidung: In einem
  /// gewöhnlichen Safari-Tab gibt es `Notification` nicht, erst in der über
  /// "Zum Home-Bildschirm" installierten App (ab iOS 16.4).
  static bool get isSupported =>
      _notificationApi != null && _serviceWorkerApi != null;

  /// Kurzschluss vor dem Punktzugriff: Ohne `Notification` im Fenster würde
  /// `Notification.permission` einen Fehler werfen.
  ///
  /// Achtung: Das ist die rohe Browser-Erlaubnis, nicht OneSignals eigene
  /// Anmeldung – für die Frage „bekommt dieses Gerät Meldungen" ist
  /// [isSubscribed] die richtige Abfrage, nicht diese hier.
  static bool get hasPermission => isSupported && _permission == 'granted';

  /// Ob OneSignal dieses Gerät wirklich als Empfänger führt.
  ///
  /// Getrennt von [hasPermission], weil das zwei verschiedene Zustände sind:
  /// Die Browser-Erlaubnis kann erteilt sein, ohne dass OneSignal je etwas
  /// davon erfahren hat – etwa wenn sie über die Browser-Einstellungen
  /// erteilt wurde statt über [requestPermission]. Im Dashboard steht das
  /// Gerät dann als „Never Subscribed", obwohl der Browser „granted" meldet.
  /// Genau das war der Fehler, der Meldungen verhindert hat.
  static Future<bool> isSubscribed() async {
    if (!isSupported) return false;
    try {
      return await _withSdk(
        (os) async => os.user.pushSubscription.optedIn ?? false,
      );
    } catch (_) {
      return false;
    }
  }

  /// Schliesst die OneSignal-Anmeldung aktiv ab. Nötig, weil sie sich nicht
  /// von selbst einstellt, nur weil der Browser die Erlaubnis erteilt hat –
  /// siehe [isSubscribed].
  static Future<void> _optIn() =>
      _withSdk((os) => os.user.pushSubscription.optIn().toDart);

  /// Leer mit Absicht: `web/index.html` ruft `OneSignal.init` bereits auf,
  /// bevor Flutter startet – dort steht auch die Service-Worker-Konfiguration,
  /// die vom Ausliefer-Pfad abhängt.
  static Future<void> initialize(String appId) async {}

  static Future<void> login(String externalId) =>
      _withSdk((os) => os.login(externalId).toDart);

  static Future<void> logout() => _withSdk((os) => os.logout().toDart);

  /// Fragt nach der Browser-Erlaubnis und schliesst danach die
  /// OneSignal-Anmeldung ab – anders als [isSubscribed] schluckt das hier
  /// keinen Fehler still, sondern meldet zurück, an welchem der drei
  /// Schritte es gescheitert ist. Nötig, weil „Browser erlaubt, OneSignal
  /// meldet trotzdem nicht an" ein anderer, anders zu behebender Fall ist
  /// als eine echte Browser-Blockade – und beides bis hierhin zum selben
  /// `false` zusammenfiel.
  static Future<PushEnableResult> requestPermission() async {
    if (!isSupported) {
      return const PushEnableResult(PushEnableOutcome.unsupported);
    }

    try {
      await _withSdk((os) => os.notifications.requestPermission().toDart);
    } catch (error) {
      // SDK kam nicht/nicht rechtzeitig an, siehe _withSdk-Frist unten –
      // etwa weil ein Inhaltsblocker das CDN-Skript ausliess.
      return PushEnableResult(PushEnableOutcome.sdkUnavailable, '$error');
    }

    // Kein Popup gemeldet heisst: Der Browser hat nicht (neu) zugestimmt.
    if (_permission != 'granted') {
      return PushEnableResult(
        PushEnableOutcome.browserDenied,
        'Notification.permission=$_permission',
      );
    }

    try {
      // Browser-Erlaubnis reicht nicht – ohne diesen Schritt bliebe die
      // OneSignal-Anmeldung offen, siehe isSubscribed.
      await _optIn();
    } catch (error) {
      return PushEnableResult(
        error is TimeoutException
            ? PushEnableOutcome.sdkUnavailable
            : PushEnableOutcome.subscriptionFailed,
        '$error',
      );
    }

    // Bewusst nicht über isSubscribed(): Die schluckt Fehler still, hier
    // soll ein Fehlschlag beim Nachlesen sichtbar bleiben statt einfach als
    // "nicht angemeldet" durchzugehen.
    Future<bool> readOptedIn() => _withSdk(
          (os) async => os.user.pushSubscription.optedIn ?? false,
        );

    bool subscribed;
    try {
      subscribed = await readOptedIn();
    } catch (error) {
      return PushEnableResult(
        error is TimeoutException
            ? PushEnableOutcome.sdkUnavailable
            : PushEnableOutcome.subscriptionFailed,
        '$error',
      );
    }

    if (!subscribed) {
      // Möglicher Wettlauf: OneSignals interner Stand könnte optIn() noch
      // nicht nachgezogen haben. Ein einmaliger kurzer Nachschlag klärt das,
      // bevor es als echter Fehlschlag gilt.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      try {
        subscribed = await readOptedIn();
      } catch (error) {
        return PushEnableResult(
          error is TimeoutException
              ? PushEnableOutcome.sdkUnavailable
              : PushEnableOutcome.subscriptionFailed,
          '$error',
        );
      }
    }

    return subscribed
        ? const PushEnableResult(PushEnableOutcome.granted)
        : const PushEnableResult(
            PushEnableOutcome.subscriptionFailed,
            'optIn() erfolgreich, optedIn bleibt aber false',
          );
  }

  static void onClick(void Function(Map<String, dynamic>? data) handler) {
    _withSdk((os) async {
      os.notifications.addEventListener(
        'click',
        ((_ClickEvent event) {
          final data = event.notification.additionalData?.dartify();
          handler(data is Map ? Map<String, dynamic>.from(data) : null);
        }).toJS,
      );
    }).catchError((Object error) {
      // Kein SDK, keine Meldungen – dann gibt es auch keine anzutippen.
    });
  }

  /// Führt [body] aus, sobald das SDK bereit ist.
  ///
  /// `OneSignalDeferred` ist eine Liste, die das SDK nach `init()` abarbeitet.
  /// Der Umweg ist nötig, weil die Anmeldung schneller sein kann als das
  /// Nachladen des SDK vom CDN – ein direkter Aufruf ginge dann ins Leere.
  ///
  /// Die Frist deckt den Fall ab, dass das SDK gar nicht kommt: Ein
  /// Inhaltsblocker im Browser lässt das CDN-Skript aus, die Liste wird dann
  /// nie abgearbeitet, und ohne Frist würde der Knopf in der Lobby ewig warten.
  static Future<T> _withSdk<T>(Future<T> Function(_OneSignal os) body) {
    final result = Completer<T>();
    try {
      _deferred.push(((JSObject os) {
        try {
          result.complete(body(_OneSignal(os)));
        } catch (error, stack) {
          if (!result.isCompleted) result.completeError(error, stack);
        }
      }).toJS);
    } catch (error, stack) {
      result.completeError(error, stack);
    }
    return result.future.timeout(const Duration(seconds: 15));
  }
}

/// Warum requestPermission() nicht zu einer Anmeldung geführt hat – wichtig
/// für die Lobby-Anzeige: nur einer der Gründe heisst wirklich "nur über die
/// Browser-Einstellungen zu beheben". Steht hier und in der nativen Brücke
/// je eigenständig, wie auch [OneSignalApi] selbst dort dupliziert ist –
/// `onesignal_bridge.dart` reicht per bedingtem Export ohnehin nur eine der
/// beiden Dateien durch.
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

  /// Rohe Fehlermeldung – nur fürs Debuggen, kein Endnutzer-Text.
  final String? detail;

  bool get granted => outcome == PushEnableOutcome.granted;
}

@JS('OneSignalDeferred')
external _Deferred get _deferred;

@JS('window.Notification')
external JSAny? get _notificationApi;

@JS('window.navigator.serviceWorker')
external JSAny? get _serviceWorkerApi;

@JS('window.Notification.permission')
external String? get _permission;

extension type _Deferred(JSObject _) implements JSObject {
  external void push(JSFunction callback);
}

extension type _OneSignal(JSObject _) implements JSObject {
  external JSPromise<JSAny?> login(String externalId);
  external JSPromise<JSAny?> logout();

  // Gross geschrieben im SDK; hier klein, damit es zu den übrigen Namen passt.
  @JS('Notifications')
  external _Notifications get notifications;

  @JS('User')
  external _User get user;
}

extension type _Notifications(JSObject _) implements JSObject {
  external JSPromise<JSAny?> requestPermission();
  external void addEventListener(String event, JSFunction listener);
}

extension type _User(JSObject _) implements JSObject {
  @JS('PushSubscription')
  external _PushSubscription get pushSubscription;
}

extension type _PushSubscription(JSObject _) implements JSObject {
  external bool? get optedIn;
  external JSPromise<JSAny?> optIn();
}

extension type _ClickEvent(JSObject _) implements JSObject {
  external _OsNotification get notification;
}

extension type _OsNotification(JSObject _) implements JSObject {
  external JSObject? get additionalData;
}
