import * as admin from "firebase-admin";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {appleKey} from "./storeConfig";
import {verifyApplePurchase} from "./appleStoreVerifier";
import {
  verifyGooglePurchase, acknowledgeGooglePurchase,
} from "./googlePlayVerifier";
import {persistSubscription} from "./subscriptionStore";
import {VerifiedSubscription} from "./subscriptionPolicy";

// Recover missed notifications and failed acknowledgements without requiring
// customers to open the app. Include inactive subscriptions so recovery from
// billing hold is found even when its notification was missed.
export const reconcileSubscriptions = onSchedule(
  {schedule: "every 6 hours", secrets: [appleKey], timeoutSeconds: 540},
  async () => {
    const db = admin.firestore();
    let cursor: admin.firestore.QueryDocumentSnapshot | undefined;
    let failed = 0;
    do {
      let query = db.collection("storeSubscriptions")
        .where("expiresAt", ">", Date.now() - 60 * 24 * 60 * 60 * 1000)
        .orderBy("expiresAt").limit(100);
      if (cursor) query = query.startAfter(cursor);
      const page = await query.get();
      if (page.empty) break;
      for (const doc of page.docs) {
        const entry = doc.data() as VerifiedSubscription & {uid: string};
        try {
          const current = entry.source === "apple" ?
            await verifyApplePurchase("", entry.id,
              entry.environment === "Sandbox") :
            await verifyGooglePurchase(entry.id);
          await persistSubscription(entry.uid, current);
          if (current.source === "google") {
            await acknowledgeGooglePurchase(current);
          }
        } catch {
          failed++;
          logger.warn("Subscription reconciliation failed", {uid: entry.uid});
        }
      }
      cursor = page.docs[page.docs.length - 1];
      if (page.size < 100) break;
    } while (cursor);
    logger.info("Subscription reconciliation completed", {failed});
    if (failed) {
      throw new Error("Some subscriptions require reconciliation retry");
    }
  },
);
