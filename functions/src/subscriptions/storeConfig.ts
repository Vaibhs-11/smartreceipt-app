import {defineSecret, defineString} from "firebase-functions/params";

export const appleKey = defineSecret("APPLE_SUBSCRIPTION_PRIVATE_KEY");
export const appleKeyId = defineString("APPLE_SUBSCRIPTION_KEY_ID");
export const appleIssuerId = defineString("APPLE_SUBSCRIPTION_ISSUER_ID");
export const appleAppId = defineString("APPLE_APP_ID");
export const bundleId = "com.vaibhs.smartreceipt";
export const googlePackage = "com.vaibhs.smartreceipt";
export const googleTopic = "receiptnest-play-subscriptions";
// Sandbox transactions are isolated from production ownership IDs and require
// an explicit server allowlist of Firebase test accounts.
export const sandboxUids = defineString("SUBSCRIPTION_SANDBOX_UIDS", {
  default: "",
});
export const googleProducts = defineString("GOOGLE_SUBSCRIPTION_PRODUCTS", {
  default: JSON.stringify({
    "com.receiptnest.premium.monthly": "monthly",
    "com.receiptnest.premium.yearly": "yearly",
  }),
});
