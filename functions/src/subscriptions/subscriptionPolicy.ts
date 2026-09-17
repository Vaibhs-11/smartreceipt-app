export type Store = "apple" | "google";
export interface VerifiedSubscription {
  source: Store;
  id: string;
  productId: string;
  tier: "monthly" | "yearly";
  expiresAt: number;
  active: boolean;
  environment: string;
  accountToken?: string;
  replacementId?: string;
  superseded?: boolean;
  observedAt: number;
}

// A subscription is eligible only while the store allows access. An expired
// subscription from one store must not override another active subscription.
export const selectEntitlement = (
  subscriptions: VerifiedSubscription[], now: number,
): VerifiedSubscription | undefined => subscriptions
  .filter((entry) => entry.active && !entry.superseded && entry.expiresAt > now)
  .sort((a, b) => b.expiresAt - a.expiresAt)[0];

export const hasLivePaidAccess = (data: {
  subscriptionStatus?: string;
  subscriptionTier?: string;
  subscriptionEndsAt?: {toMillis(): number};
}, now: number): boolean => data.subscriptionStatus === "active" &&
  ["monthly", "yearly"].includes(data.subscriptionTier ?? "") &&
  (data.subscriptionEndsAt === undefined ||
    data.subscriptionEndsAt === null ||
    data.subscriptionEndsAt.toMillis() > now);

export const entitlementPatch = (
  entries: VerifiedSubscription[], now: number,
): Record<string, unknown> => {
  const active = selectEntitlement(entries, now);
  const latest = active ?? [...entries]
    .sort((a, b) => b.expiresAt - a.expiresAt)[0];
  if (!latest) return {}; // An empty restore never changes free/trial state.
  return {
    subscriptionStatus: active ? "active" : "expired",
    subscriptionTier: active?.tier ?? "free",
    subscriptionSource: latest.source,
    subscriptionEndsAtMillis: latest.expiresAt,
    ...(active ? {trialDowngradeRequired: false} : {}),
  };
};
