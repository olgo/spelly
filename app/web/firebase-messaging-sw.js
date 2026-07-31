// Nimmt Push-Meldungen entgegen, während die Web-App geschlossen ist.
// Muss im Wurzelverzeichnis liegen und genau so heissen – der Name ist von
// Firebase vorgegeben.
//
// Die Werte hier sind öffentlich; das ist bei Firebase-Web-Konfigurationen so
// vorgesehen. Der Schutz kommt aus den Sicherheitsregeln, nicht aus Geheimhaltung.

importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'HIER_EINTRAGEN',
  authDomain: 'HIER_EINTRAGEN',
  projectId: 'HIER_EINTRAGEN',
  messagingSenderId: 'HIER_EINTRAGEN',
  appId: 'HIER_EINTRAGEN',
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  self.registration.showNotification(title ?? 'Spelly', {
    body: body ?? '',
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    // Eine neuere Meldung zur selben Partie ersetzt die ältere.
    tag: payload.data?.game_id,
    data: payload.data,
  });
});

// Antippen öffnet die Partie statt nur die Startseite.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  const route = event.notification.data?.route ?? '/';
  event.waitUntil(
    clients.matchAll({ type: 'window', includeUncontrolled: true }).then((list) => {
      for (const client of list) {
        if ('focus' in client) return client.focus();
      }
      return clients.openWindow(route);
    })
  );
});
