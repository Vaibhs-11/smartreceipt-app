import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

type SubscriptionTier = "free" | "monthly" | "yearly";
type SubscriptionStatus = "active" | "expired" | "none";
type SubscriptionSource = "apple" | "google";

const SUBSCRIPTION_TIERS = new Set<SubscriptionTier>([
  "free",
  "monthly",
  "yearly",
]);
const SUBSCRIPTION_STATUSES = new Set<SubscriptionStatus>([
  "active",
  "expired",
  "none",
]);
const SUBSCRIPTION_SOURCES = new Set<SubscriptionSource>([
  "apple",
  "google",
]);

const asTier = (value: unknown): SubscriptionTier => {
  if (typeof value !== "string") return "free";
  return SUBSCRIPTION_TIERS.has(value as SubscriptionTier) ?
    (value as SubscriptionTier) :
    "free";
};

const asStatus = (value: unknown): SubscriptionStatus => {
  if (typeof value !== "string") return "none";
  return SUBSCRIPTION_STATUSES.has(value as SubscriptionStatus) ?
    (value as SubscriptionStatus) :
    "none";
};

const asSource = (value: unknown): SubscriptionSource | null => {
  if (typeof value !== "string") return null;
  return SUBSCRIPTION_SOURCES.has(value as SubscriptionSource) ?
    (value as SubscriptionSource) :
    null;
};

export const syncSubscriptionEntitlement = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const firestore = admin.firestore();
  const userRef = firestore.collection("users").doc(uid);

  const tier = asTier(request.data?.tier);
  const status = asStatus(request.data?.status);
  const source = asSource(request.data?.source);
  const updatedAtMillis = request.data?.updatedAtMillis;

  let updatedAt = admin.firestore.Timestamp.now();
  if (typeof updatedAtMillis === "number" &&
    Number.isFinite(updatedAtMillis)) {
    updatedAt = admin.firestore.Timestamp.fromMillis(updatedAtMillis);
  }

  const payload: Record<string, unknown> = {
    subscriptionTier: status === "active" ? tier : "free",
    subscriptionStatus: status,
    subscriptionUpdatedAt: updatedAt,
  };
  if (source) {
    payload["subscriptionSource"] = source;
  }

  await userRef.set(payload, {merge: true});
  return {status: "updated"};
});
