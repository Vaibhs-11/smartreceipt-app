import {GoogleAuth} from "google-auth-library";
import {HttpsError} from "firebase-functions/v2/https";
import {googlePackage, googleProducts} from "./storeConfig";
import {VerifiedSubscription} from "./subscriptionPolicy";

const auth = new GoogleAuth({
  scopes: ["https://www.googleapis.com/auth/androidpublisher"],
});
const base = "https://androidpublisher.googleapis.com/androidpublisher/v3" +
  `/applications/${googlePackage}/purchases/subscriptions`;
export interface PlaySubscription {
  subscriptionState?: string;
  acknowledgementState?: string;
  testPurchase?: object;
  linkedPurchaseToken?: string;
  externalAccountIdentifiers?: {obfuscatedExternalAccountId?: string};
  lineItems?: {
    productId: string; expiryTime?: string;
    offerDetails?: {basePlanId?: string};
  }[];
}
export const verifyGooglePurchase = async (
  token: string,
): Promise<VerifiedSubscription> => {
  const observedAt = Date.now();
  const client = await auth.getClient();
  const {data} = await client.request<PlaySubscription>({
    url: `${base}v2/tokens/${encodeURIComponent(token)}`,
  });
  const products = JSON.parse(googleProducts.value()) as Record<string, string>;
  return normalizeGoogleSubscription(data, token, products, observedAt);
};

export const normalizeGoogleSubscription = (
  data: PlaySubscription, token: string,
  products: Record<string, string>, observedAt: number,
): VerifiedSubscription => {
  const items = (data.lineItems ?? []).map((item) => ({
    ...item,
    tier: products[`${item.productId}:${item.offerDetails?.basePlanId}`] ??
      products[item.productId],
  })).filter((item) => ["monthly", "yearly"].includes(item.tier))
    .sort((a, b) => Date.parse(b.expiryTime ?? "") -
      Date.parse(a.expiryTime ?? ""));
  const item = items[0];
  const expiresAt = Date.parse(item?.expiryTime ?? "");
  if (!item || !Number.isFinite(expiresAt)) {
    throw new HttpsError("failed-precondition", "No completed subscription");
  }
  return {
    source: "google", id: token, productId: item.productId,
    tier: item.tier as "monthly" | "yearly", expiresAt,
    active: ["SUBSCRIPTION_STATE_ACTIVE", "SUBSCRIPTION_STATE_CANCELED",
      "SUBSCRIPTION_STATE_IN_GRACE_PERIOD"].includes(
      data.subscriptionState ?? ""),
    environment: data.testPurchase ? "Sandbox" : "Production",
    accountToken:
      data.externalAccountIdentifiers?.obfuscatedExternalAccountId,
    replacementId: data.linkedPurchaseToken, observedAt,
  };
};

export const acknowledgeGooglePurchase = async (
  subscription: VerifiedSubscription,
): Promise<void> => {
  if (!subscription.active || subscription.expiresAt <= Date.now()) return;
  const client = await auth.getClient();
  const {data} = await client.request<PlaySubscription>({
    url: `${base}v2/tokens/${encodeURIComponent(subscription.id)}`,
  });
  if (data.acknowledgementState === "ACKNOWLEDGEMENT_STATE_ACKNOWLEDGED") {
    return;
  }
  await client.request({
    url: `${base}/${encodeURIComponent(subscription.productId)}/tokens/` +
      `${encodeURIComponent(subscription.id)}:acknowledge`,
    method: "POST", data: {},
  });
};
