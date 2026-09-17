import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {assertPayloadSize, assertUserRateLimit} from "../security/rateLimit";
import {appleKey} from "./storeConfig";
import {verifyApplePurchase} from "./appleStoreVerifier";
import {
  acknowledgeGooglePurchase, verifyGooglePurchase,
} from "./googlePlayVerifier";
import {accountTokenFor, persistSubscription} from "./subscriptionStore";

export const getSubscriptionAccountToken = onCall(
  {enforceAppCheck: true}, async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in first");
    const config = await admin.firestore().doc("config/app").get();
    if (config.get("enableSubscriptionPurchases") !== true ||
        config.get("enablePaidTiers") === false) {
      throw new HttpsError("failed-precondition",
        "New subscriptions unavailable");
    }
    if (request.auth.token.firebase?.sign_in_provider === "anonymous") {
      throw new HttpsError("failed-precondition", "Create an account first");
    }
    return {token: await accountTokenFor(request.auth.uid)};
  },
);

export const syncSubscriptionEntitlement = onCall(
  {enforceAppCheck: true, secrets: [appleKey]}, async (request) => {
    const uid = request.auth?.uid;
    if (!uid) throw new HttpsError("unauthenticated", "Sign in first");
    if (request.auth?.token.firebase?.sign_in_provider === "anonymous") {
      throw new HttpsError("failed-precondition", "Create an account first");
    }
    const {
      source, verificationData, expectedUid, restore,
    } = request.data ?? {};
    assertPayloadSize(request.data, 110000);
    await assertUserRateLimit({firestore: admin.firestore(), uid,
      functionName: "syncSubscriptionEntitlement", maxCalls: 120});
    if (expectedUid !== uid) {
      throw new HttpsError("permission-denied",
        "Account changed; retry restore");
    }
    if (!["apple", "google"].includes(source) ||
        typeof verificationData !== "string" ||
        !verificationData || verificationData.length > 100000) {
      throw new HttpsError("invalid-argument", "Purchase evidence required");
    }
    try {
      const verified = source === "apple" ?
        await verifyApplePurchase(verificationData) :
        await verifyGooglePurchase(verificationData);
      const result = await persistSubscription(uid, verified, restore === true);
      if (source === "google") await acknowledgeGooglePurchase(verified);
      logger.info("Subscription verified", {
        uid, source, tier: result.tier, status: result.status,
      });
      return result;
    } catch (error) {
      // Raw store exceptions can contain purchase tokens. Never log them.
      logger.warn("Subscription verification failed", {
        uid, source,
        code: error instanceof HttpsError ? error.code : "store-unavailable",
      });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError("unavailable", "Unable to verify; retry restore");
    }
  },
);
