import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {onSchedule} from "firebase-functions/v2/scheduler";

export const aggregateDailyMetrics = onSchedule("every day 00:00", async () => {
  try {
    const now = new Date();
    const startOfTodayUtc = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate()
    ));
    const startOfYesterdayUtc = new Date(startOfTodayUtc);
    startOfYesterdayUtc.setUTCDate(startOfYesterdayUtc.getUTCDate() - 1);

    const date = startOfYesterdayUtc.toISOString().slice(0, 10);
    const firestore = admin.firestore();

    const snapshot = await firestore
      .collection("analytics_events")
      .where(
        "createdAt",
        ">=",
        admin.firestore.Timestamp.fromDate(startOfYesterdayUtc)
      )
      .where(
        "createdAt",
        "<",
        admin.firestore.Timestamp.fromDate(startOfTodayUtc)
      )
      .get();

    let receipts = 0;
    let trialsStarted = 0;
    let premiumActivated = 0;
    let enrichmentSuccess = 0;
    let enrichmentFailed = 0;
    const activeUsers = new Set<string>();

    for (const doc of snapshot.docs) {
      const data = doc.data();
      const eventName =
        typeof data["eventName"] === "string" ? data["eventName"] : "";
      const userId = typeof data["userId"] === "string" ? data["userId"] : "";

      if (userId) {
        activeUsers.add(userId);
      }

      switch (eventName) {
      case "receipt_created":
        receipts += 1;
        break;
      case "trial_started":
        trialsStarted += 1;
        break;
      case "premium_activated":
        premiumActivated += 1;
        break;
      case "enrichment_completed":
        enrichmentSuccess += 1;
        break;
      case "enrichment_failed":
        enrichmentFailed += 1;
        break;
      default:
        break;
      }
    }

    await firestore.collection("metrics_daily").doc(date).set({
      date,
      receipts,
      trialsStarted,
      premiumActivated,
      enrichmentSuccess,
      enrichmentFailed,
      activeUsers: activeUsers.size,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.error("Failed to aggregate daily analytics metrics", {error});
  }
});
