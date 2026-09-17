import {test} from "node:test";
import assert from "node:assert/strict";
import * as admin from "firebase-admin";
import {persistSubscription} from "../subscriptionStore";
import {VerifiedSubscription} from "../subscriptionPolicy";
import {normalizeGoogleSubscription} from "../googlePlayVerifier";

// Transaction test double: staged writes commit only after a successful body.
const fixture = (user: Record<string, unknown>) => {
  const docs = new Map<string, Record<string, unknown>>([
    ["users/u1", user], ["subscriptionAccounts/u1", {token: "account-1"}],
    ["users/u2", user], ["subscriptionAccounts/u2", {token: "account-2"}],
  ]);
  const collection = (name: string) => ({doc: (id: string) => `${name}/${id}`});
  const db = {
    collection,
    runTransaction: async (body: (tx: unknown) => Promise<unknown>) => {
      const writes: [string, Record<string, unknown>][] = [];
      const result = await body({
        get: async (path: string) => ({
          exists: docs.has(path),
          get: (key: string) => {
            const value = docs.get(path)?.[key];
            return key === "subscriptions" && value ?
              JSON.parse(JSON.stringify(value)) : value;
          },
        }),
        set: (path: string, data: Record<string, unknown>) => {
          writes.push([path, data]);
        },
      });
      for (const [path, data] of writes) {
        docs.set(path, {...docs.get(path), ...data});
      }
      return result;
    },
  } as unknown as admin.firestore.Firestore;
  return {db, docs};
};
const entry = (overrides: Partial<VerifiedSubscription> = {}) => ({
  source: "apple" as const, id: "original", productId: "monthly",
  tier: "monthly" as const, expiresAt: Date.now() + 1000000,
  active: true, environment: "Production", accountToken: "account-1",
  observedAt: 100, ...overrides,
});
const trial = {
  accountStatus: "trial", trialUsed: true, trialStartedAt: 10,
  trialEndsAt: 20, trialDowngradeRequired: true,
  subscriptionStatus: "none", subscriptionTier: "free",
};

test("verified activation preserves trial history", async () => {
  const {db, docs} = fixture(trial);
  await persistSubscription("u1", entry(), false, db);
  const user = docs.get("users/u1");
  for (const field of ["accountStatus", "trialUsed",
    "trialStartedAt", "trialEndsAt"] as const) {
    assert.equal(user?.[field], trial[field]);
  }
  assert.equal(user?.subscriptionStatus, "active");
  assert.equal(user?.trialDowngradeRequired, false);
});
for (const accountStatus of ["free", "trial"]) {
  test(
    `expired restore leaves ${accountStatus} profile untouched`, async () => {
      const profile = {...trial, accountStatus};
      const {db, docs} = fixture(profile);
      await persistSubscription("u1", entry({active: false}), true, db);
      assert.deepEqual(docs.get("users/u1"), profile);
    });
}
test("ownership and token mismatch cannot grant", async () => {
  const {db, docs} = fixture(trial);
  await persistSubscription("u1", entry(), false, db);
  await assert.rejects(persistSubscription("u2", entry(), true, db));
  await assert.rejects(persistSubscription("u2",
    entry({id: "another"}), true, db));
  assert.deepEqual(docs.get("users/u2"), trial);
});
test("legacy proof requires restore and binds once", async () => {
  const {db} = fixture(trial);
  const proof = entry({accountToken: undefined});
  await assert.rejects(persistSubscription("u1", proof, false, db));
  await persistSubscription("u1", proof, true, db);
  await assert.rejects(persistSubscription("u2", proof, true, db));
});
test("cleanup lock prevents concurrent activation", async () => {
  const {db, docs} = fixture(trial);
  docs.set("subscriptionAccounts/u1", {
    token: "account-1", downgradeInProgress: true,
  });
  await assert.rejects(persistSubscription("u1", entry(), false, db));
  assert.deepEqual(docs.get("users/u1"), trial);
});
test("stale response cannot undo newer revocation", async () => {
  const {db, docs} = fixture(trial);
  await persistSubscription("u1", entry(), false, db);
  await persistSubscription("u1",
    entry({active: false, observedAt: 200}), false, db);
  await persistSubscription("u1", entry(), false, db);
  assert.equal(docs.get("users/u1")?.subscriptionStatus, "expired");
});
test("expiry of one store preserves the other store's access", async () => {
  const {db, docs} = fixture(trial);
  await persistSubscription("u1", entry(), false, db);
  await persistSubscription("u1",
    entry({source: "google", active: false}), false, db);
  assert.equal(docs.get("users/u1")?.subscriptionStatus, "active");
  assert.equal(docs.get("users/u1")?.subscriptionSource, "apple");
});
test("sandbox evidence is not granted to production accounts", async () => {
  const {db} = fixture(trial);
  await assert.rejects(persistSubscription("u1",
    entry({environment: "Sandbox"}), true, db));
});
for (const [state, active] of Object.entries({
  ACTIVE: true, CANCELED: true, IN_GRACE_PERIOD: true,
  ON_HOLD: false, PAUSED: false, EXPIRED: false, PENDING: false,
})) {
  test(`Google state ${state} eligibility`, () => {
    const result = normalizeGoogleSubscription({
      subscriptionState: `SUBSCRIPTION_STATE_${state}`,
      lineItems: [{productId: "premium", expiryTime: "2099-01-01T00:00:00Z",
        offerDetails: {basePlanId: "monthly"}}],
    }, "token", {"premium:monthly": "monthly"}, 100);
    assert.equal(result.active, active);
    assert.equal(result.tier, "monthly");
  });
}
test("unknown Google product cannot grant entitlement", () => {
  assert.throws(() => normalizeGoogleSubscription({lineItems: [{
    productId: "unknown", expiryTime: "2099-01-01T00:00:00Z",
  }]}, "token", {}, 100));
});
