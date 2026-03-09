import * as functions from "firebase-functions";
import * as admin from "firebase-admin";

admin.initializeApp();

// Placeholder -- full implementation in YES-3
export const onRequestCreated = functions.firestore
  .document("requests/{requestId}")
  .onCreate(async (snap, context) => {
    functions.logger.info("New request created", { requestId: context.params.requestId });
  });
