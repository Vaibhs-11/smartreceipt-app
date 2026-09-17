import * as admin from "firebase-admin";
import {createHash, randomUUID} from "node:crypto";
import {HttpsError} from "firebase-functions/v2/https";
import {entitlementPatch, VerifiedSubscription} from "./subscriptionPolicy";
import {sandboxUids} from "./storeConfig";

export const subscriptionKey = (entry: {
  source: string; environment: string; id: string;
}): string => createHash("sha256")
  .update(`${entry.source}:${entry.environment}:${entry.id}`).digest("hex");

export const accountTokenFor = async (uid: string): Promise<string> => {
  const db = admin.firestore();
  const ref = db.collection("subscriptionAccounts").doc(uid);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const existing = snap.get("token") as string | undefined;
    if (existing) return existing;
    const token = randomUUID();
    tx.set(ref, {token}, {merge: true});
    tx.create(db.collection("subscriptionAccountTokens").doc(token), {uid});
    return token;
  });
};

export const findSubscriptionOwner = async (
  entry: VerifiedSubscription,
): Promise<string | undefined> => {
  const db = admin.firestore();
  const owner = await db.collection("storeSubscriptions")
    .doc(subscriptionKey(entry)).get();
  if (owner.exists) return owner.get("uid") as string;
  if (!entry.accountToken) return undefined;
  const token = await db.collection("subscriptionAccountTokens")
    .doc(entry.accountToken).get();
  return token.get("uid") as string | undefined;
};

export const persistSubscription = async (
  uid: string, entry: VerifiedSubscription, allowLegacyClaim = false,
  db: admin.firestore.Firestore = admin.firestore(),
): Promise<Record<string, unknown>> => {
  if (entry.environment !== "Production" &&
      !sandboxUids.value().split(",").map((s) => s.trim()).includes(uid)) {
    throw new HttpsError("permission-denied", "Test account not enabled");
  }
  const account = db.collection("subscriptionAccounts").doc(uid);
  const user = db.collection("users").doc(uid);
  const key = subscriptionKey(entry);
  const owner = db.collection("storeSubscriptions").doc(key);
  return db.runTransaction(async (tx) => {
    const [accountSnap, userSnap, ownerSnap] = await Promise.all([
      tx.get(account), tx.get(user), tx.get(owner),
    ]);
    if (!userSnap.exists) {
      throw new HttpsError("failed-precondition", "User profile missing");
    }
    if (accountSnap.get("downgradeInProgress") === true) {
      throw new HttpsError("unavailable", "Account cleanup in progress; retry");
    }
    if (ownerSnap.exists && ownerSnap.get("uid") !== uid) {
      throw new HttpsError("already-exists",
        "Purchase belongs to another account");
    }
    const token = accountSnap.get("token") as string | undefined;
    if (entry.accountToken && entry.accountToken !== token) {
      throw new HttpsError("permission-denied", "Purchase account mismatch");
    }
    if (!ownerSnap.exists && !entry.accountToken && !allowLegacyClaim) {
      throw new HttpsError("failed-precondition",
        "Restore purchase to link account");
    }
    const entries = (accountSnap.get("subscriptions") ?? {}) as
      Record<string, VerifiedSubscription>;
    if (entry.replacementId) {
      const replacementKey = subscriptionKey({
        ...entry, id: entry.replacementId,
      });
      const previousOwner = await tx.get(db.collection("storeSubscriptions")
        .doc(replacementKey));
      if (previousOwner.exists && previousOwner.get("uid") !== uid) {
        throw new HttpsError("permission-denied",
          "Replacement account mismatch");
      }
      if (entries[replacementKey]) entries[replacementKey].superseded = true;
    }
    // A response fetched before a newer reconciliation cannot roll it back.
    if (!entries[key] || entries[key].observedAt <= entry.observedAt) {
      const clean = JSON.parse(JSON.stringify(entry)) as VerifiedSubscription;
      if (entries[key]?.superseded) clean.superseded = true;
      entries[key] = clean;
      tx.set(owner, {uid, ...clean}, {merge: true});
    }
    const patch = entitlementPatch(Object.values(entries), Date.now());
    const millis = patch.subscriptionEndsAtMillis as number;
    delete patch.subscriptionEndsAtMillis;
    tx.set(account, {subscriptions: entries}, {merge: true});
    if (patch.subscriptionStatus === "active" ||
        ["active", "expired"].includes(userSnap.get("subscriptionStatus"))) {
      tx.set(user, {
        ...patch,
        subscriptionEndsAt: admin.firestore.Timestamp.fromMillis(millis),
        subscriptionUpdatedAt: admin.firestore.FieldValue.serverTimestamp(),
      }, {merge: true});
    } // Preserve all trial fields and accountStatus.
    return {
      accepted: true, tier: patch.subscriptionTier,
      status: patch.subscriptionStatus, source: patch.subscriptionSource,
      expiresAtMillis: millis,
    };
  });
};
