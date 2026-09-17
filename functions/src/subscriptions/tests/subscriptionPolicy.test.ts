import {test} from "node:test";
import {strict as assert} from "node:assert";
import {
  entitlementPatch, hasLivePaidAccess, selectEntitlement, VerifiedSubscription,
} from "../subscriptionPolicy";
const now = 100000;
const paid: VerifiedSubscription = {
  source: "apple", id: "tx", tier: "monthly", expiresAt: now + 1000,
  productId: "monthly", active: true,
  environment: "Production", observedAt: now,
};
test("empty restore cannot change any account fields", () => {
  assert.deepEqual(entitlementPatch([], now), {});
});
test("activation preserves trial history and clears downgrade", () => {
  const patch = entitlementPatch([paid], now);
  assert.equal(patch.subscriptionStatus, "active");
  assert.equal(patch.trialDowngradeRequired, false);
  const protectedFields = [
    "accountStatus", "trialUsed", "trialStartedAt", "trialEndsAt",
  ];
  for (const key of protectedFields) {
    assert.equal(key in patch, false);
  }
});
test("Google expiry cannot revoke active Apple access", () => {
  const expired = {
    ...paid, source: "google" as const, id: "token", active: false,
  };
  assert.equal(selectEntitlement([expired, paid], now)?.source, "apple");
});
test("Apple revocation cannot revoke active Google access", () => {
  const google = {...paid, source: "google" as const};
  assert.equal(selectEntitlement([
    {...paid, active: false}, google,
  ], now)?.source, "google");
});
test("expired or superseded proof cannot grant access", () => {
  assert.equal(selectEntitlement([{...paid, expiresAt: now}], now), undefined);
  assert.equal(selectEntitlement([
    {...paid, superseded: true},
  ], now), undefined);
});
test("expiry never writes trial or destructive downgrade state", () => {
  const patch = entitlementPatch([{...paid, expiresAt: now}], now);
  assert.equal(patch.subscriptionStatus, "expired");
  assert.equal("trialDowngradeRequired" in patch, false);
  assert.equal("accountStatus" in patch, false);
});
test("legacy paid records without expiry retain compatibility", () => {
  assert.equal(hasLivePaidAccess({
    subscriptionStatus: "active", subscriptionTier: "monthly",
  }, now), true);
  assert.equal(hasLivePaidAccess({
    subscriptionStatus: "active", subscriptionTier: "monthly",
    subscriptionEndsAt: {toMillis: () => now}}, now), false);
  assert.equal(hasLivePaidAccess({}, now), false);
});
