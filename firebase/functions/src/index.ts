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

      if (data.secretToken !== deviceData.secretToken) {
        functions.logger.error("Secret token mismatch", {
          requestId,
          deviceId: data.deviceId,
        });
        return;
      }

      // Rate limit check
      const userQuery = await db.collection("users")
        .where("devices", "array-contains", data.deviceId)
        .limit(1)
        .get();

      if (!userQuery.empty) {
        const userDoc = userQuery.docs[0];
        const userData = userDoc.data();
        const tier = userData.tier || "anonymous";

        const tierConfig = await db.collection("config").doc("tiers").get();
        const limits = tierConfig.data()?.[tier];

        if (limits) {
          const now = new Date();
          let isOverLimit = false;

          if (limits.dailyLimit !== undefined) {
            const resetAt = userData.dailyResetAt?.toDate() || new Date(0);
            const todayStart = new Date(now.toISOString().split("T")[0]);
            const count = resetAt < todayStart ? 0 : userData.dailyCount || 0;
            isOverLimit = count >= limits.dailyLimit;
          }
          if (limits.monthlyLimit !== undefined) {
            const resetAt = userData.monthlyResetAt?.toDate() || new Date(0);
            const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);
            const count = resetAt < monthStart ? 0 : userData.monthlyCount || 0;
            isOverLimit = count >= limits.monthlyLimit;
          }

          if (isOverLimit) {
            await snap.ref.update({
              status: "responded",
              response: "Deny",
              rateLimited: true,
            });
            functions.logger.info("Rate limited request", {
              requestId,
              deviceId: data.deviceId,
              tier,
            });
            return;
          }

          // Increment counters
          await userDoc.ref.update({
            dailyCount: admin.firestore.FieldValue.increment(1),
            monthlyCount: admin.firestore.FieldValue.increment(1),
          });
        }
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
      functions.logger.info("No expired requests to clean up");
      return;
    }

    try {
      const batch = db.batch();
      expired.docs.forEach((doc) => {
        batch.update(doc.ref, {
          status: "responded",
          response: "Deny",
        });
      });

      await batch.commit();
      functions.logger.info("Cleaned up expired requests", { count: expired.size });
    } catch (error) {
      functions.logger.error("Failed to clean up expired requests", { error });
    }
  });

export const resetDailyCounters = functions.pubsub
  .schedule("every day 00:00")
  .timeZone("UTC")
  .onRun(async () => {
    const users = await db.collection("users").get();
    if (users.empty) {
      functions.logger.info("No users to reset daily counters");
      return;
    }

    const batch = db.batch();
    for (const doc of users.docs) {
      batch.update(doc.ref, {
        dailyCount: 0,
        dailyResetAt: admin.firestore.Timestamp.now(),
      });
    }
    await batch.commit();
    functions.logger.info("Reset daily counters", { count: users.size });
  });

export const archiveToHistory = functions.firestore
  .document("requests/{requestId}")
  .onUpdate(async (change, context) => {
    const before = change.before.data();
    const after = change.after.data();
    const requestId = context.params.requestId;

    if (before.status !== "pending" || after.status !== "responded") return;
    if (after.rateLimited) return;

    try {
      const userQuery = await db.collection("users")
        .where("devices", "array-contains", after.deviceId)
        .limit(1)
        .get();

      if (userQuery.empty) {
        functions.logger.warn("No user found for device, skipping history", {
          requestId,
          deviceId: after.deviceId,
        });
        return;
      }

      const uid = userQuery.docs[0].id;

      await db.collection("users").doc(uid).collection("history").doc(requestId).set({
        command: after.command || "",
        choices: after.choices || [],
        response: after.response || "",
        source: after.source || "claude",
        sessionLabel: after.sessionLabel || "",
        machineId: after.machineId || "",
        deviceId: after.deviceId || "",
        createdAt: after.createdAt || null,
        respondedAt: admin.firestore.Timestamp.now(),
      });

      functions.logger.info("Archived request to history", { requestId, uid });
    } catch (error) {
      functions.logger.error("Failed to archive request to history", { requestId, error });
    }
  });

export const resetMonthlyCounters = functions.pubsub
  .schedule("1 of month 00:00")
  .timeZone("UTC")
  .onRun(async () => {
    const users = await db.collection("users").get();
    if (users.empty) {
      functions.logger.info("No users to reset monthly counters");
      return;
    }

    const batch = db.batch();
    for (const doc of users.docs) {
      batch.update(doc.ref, {
        monthlyCount: 0,
        monthlyResetAt: admin.firestore.Timestamp.now(),
      });
    }
    await batch.commit();
    functions.logger.info("Reset monthly counters", { count: users.size });
  });
