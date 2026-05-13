importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

// Replace YOUR_WEB_API_KEY and YOUR_WEB_APP_ID with the values from
// lib/firebase_options.dart after running: flutterfire configure --platforms=android,web
firebase.initializeApp({
  apiKey: "AIzaSyCiV3CI9QFlh8mqOHpu9U4JYbOOpajiibM",
  authDomain: "ura-core-9981c.firebaseapp.com",
  projectId: "ura-core-9981c",
  storageBucket: "ura-core-9981c.firebasestorage.app",
  messagingSenderId: "624182997032",
  appId: "1:624182997032:web:7102d58e974ccfe57c051d",
});

const messaging = firebase.messaging();

messaging.onBackgroundMessage((payload) => {
  const { title, body } = payload.notification ?? {};
  const route = payload.data?.route ?? '';
  let tag = null;
  if (route.startsWith('/chat/')) tag = `chat_${route.slice('/chat/'.length)}`;
  else if (route.startsWith('/order/')) tag = `order_${route.slice('/order/'.length)}`;
  self.registration.showNotification(title ?? 'URA', {
    body,
    ...(tag ? { tag } : {}),
  });
});
