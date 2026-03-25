/* eslint-disable require-jsdoc */
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

/**
 * Logs analytics events to Firestore.
 * This is a non-blocking helper and failures are safely ignored.
 */
export async function logEvent({
  userId,
  eventName,
  params = {},
}: {
  userId: string;
  eventName: string;
  params?: Record<string, unknown>;
}) {
  try {
    await admin.firestore().collection("analytics_events").add({
      userId,
      eventName,
      params,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.error("Failed to log analytics event", {
      userId,
      eventName,
      error,
    });
  }
}
