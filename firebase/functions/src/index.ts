import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

export const onRequestCreated = functions.firestore
  .document("requests/{requestId}")
  .onCreate(async (snap, context) => {
    const requestId = context.params.requestId;
    const data = snap.data();

    if (!data.deviceId) {
      functions.logger.error("Request missing deviceId", { requestId });
      return;
    }

    try {
      const deviceDoc = await db.collection("devices").doc(data.deviceId).get();
      if (!deviceDoc.exists) {
        functions.logger.error("Device not found", { deviceId: data.deviceId });
        return;
      }

      const deviceData = deviceDoc.data();
      if (!deviceData?.fcmToken) {
        functions.logger.error("Device has no FCM token", { deviceId: data.deviceId });
        return;
      }

      await messaging.send({
        token: deviceData.fcmToken,
        notification: {
          title: "Yes Claude...",
          body: data.command || "Permission request",
        },
        data: {
          requestId: requestId,
          command: data.command || "",
          choices: JSON.stringify(data.choices || ["Allow", "Deny"]),
        },
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              contentAvailable: true,
            },
          },
        },
      });

      functions.logger.info("Push notification sent", { requestId, deviceId: data.deviceId });
    } catch (error) {
      functions.logger.error("Failed to send push notification", { requestId, error });
    }
  });

export const cleanupExpiredRequests = functions.pubsub
  .schedule("every 5 minutes")
  .onRun(async () => {
    const now = admin.firestore.Timestamp.now();

    const expired = await db
      .collection("requests")
      .where("status", "==", "pending")
      .where("expiresAt", "<=", now)
      .get();

    if (expired.empty) {
      return;
    }

    const batch = db.batch();
    expired.docs.forEach((doc) => {
      batch.update(doc.ref, {
        status: "expired",
        response: "Deny",
      });
    });

    await batch.commit();
    functions.logger.info("Cleaned up expired requests", { count: expired.size });
  });
