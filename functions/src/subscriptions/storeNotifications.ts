import {onRequest} from "firebase-functions/v2/https";
import {onMessagePublished} from "firebase-functions/v2/pubsub";
import * as logger from "firebase-functions/logger";
import {appleKey, googlePackage, googleTopic} from "./storeConfig";
import {
  verifyAppleNotification, verifyApplePurchase,
} from "./appleStoreVerifier";
import {
  verifyGooglePurchase, acknowledgeGooglePurchase,
} from "./googlePlayVerifier";
import {findSubscriptionOwner, persistSubscription} from "./subscriptionStore";
import {VerifiedSubscription} from "./subscriptionPolicy";

const processSubscription = async (entry: VerifiedSubscription) => {
  const uid = await findSubscriptionOwner(entry);
  if (!uid) {
    logger.warn("Subscription notification has no linked account", {
      source: entry.source,
    });
    return; // Legacy purchases must be restored in the app to link them.
  }
  await persistSubscription(uid, entry);
  if (entry.source === "google") await acknowledgeGooglePurchase(entry);
};

export const appStoreNotifications = onRequest(
  {secrets: [appleKey]}, async (request, response) => {
    if (request.method !== "POST" ||
        typeof request.body?.signedPayload !== "string" ||
        request.body.signedPayload.length > 100000) {
      response.sendStatus(400);
      return;
    }
    try {
      const notification = await verifyAppleNotification(
        request.body.signedPayload,
      );
      if (notification.notificationType === "TEST") {
        response.sendStatus(200);
        return;
      }
      const proof = notification.data?.signedTransactionInfo;
      if (proof) await processSubscription(await verifyApplePurchase(proof));
      response.sendStatus(200);
    } catch {
      logger.error("Apple subscription notification failed");
      response.sendStatus(503);
    }
  },
);

export const googlePlayNotifications = onMessagePublished(
  {topic: googleTopic, retry: true}, async (event) => {
    const data = event.data.message.json;
    if (data.packageName !== googlePackage || data.testNotification) return;
    const token = data.subscriptionNotification?.purchaseToken ??
      data.voidedPurchaseNotification?.purchaseToken;
    if (typeof token !== "string" || !token || token.length > 10000) return;
    try {
      await processSubscription(await verifyGooglePurchase(token));
    } catch {
      logger.error("Google subscription notification failed");
      throw new Error("Subscription notification requires retry");
    }
  },
);
