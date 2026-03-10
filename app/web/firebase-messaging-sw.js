// Firebase Cloud Messaging Service Worker for Yes Claude... web app
// This runs in the background to receive push notifications when the tab is not focused.

importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js");
importScripts("https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js");

// Firebase config — must match the config in your Flutter app's firebase_options.dart
// These are safe to expose in client-side code (they identify the project, not grant access).
firebase.initializeApp({
  // TODO: Replace with actual Firebase config from firebase_options.dart
  apiKey: "YOUR_API_KEY",
  authDomain: "YOUR_PROJECT.firebaseapp.com",
  projectId: "YOUR_PROJECT_ID",
  storageBucket: "YOUR_PROJECT.appspot.com",
  messagingSenderId: "YOUR_SENDER_ID",
  appId: "YOUR_APP_ID",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const title = payload.notification?.title || "Yes Claude...";
  const body = payload.notification?.body || "Permission request";
  const options = {
    body: body,
    icon: "/icons/Icon-192.png",
    badge: "/icons/Icon-192.png",
    tag: "yes-claude-request",
    renotify: true,
    data: payload.data,
  };
  return self.registration.showNotification(title, options);
});

self.addEventListener("notificationclick", (event) => {
  event.notification.close();
  event.waitUntil(
    clients.matchAll({ type: "window", includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if (client.url.includes(self.location.origin) && "focus" in client) {
          return client.focus();
        }
      }
      return clients.openWindow("/");
    })
  );
});
