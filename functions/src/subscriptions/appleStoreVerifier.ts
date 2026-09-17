import {
  AppStoreServerAPIClient, Environment, SignedDataVerifier,
} from "@apple/app-store-server-library";
import {readFileSync} from "node:fs";
import {join} from "node:path";
import {HttpsError} from "firebase-functions/v2/https";
import {
  appleAppId, appleIssuerId, appleKey, appleKeyId, bundleId,
} from "./storeConfig";
import {VerifiedSubscription} from "./subscriptionPolicy";

export const appleVerifier = (environment: Environment): SignedDataVerifier =>
  new SignedDataVerifier(
    ["AppleRootCA-G2.cer", "AppleRootCA-G3.cer"].map((file) =>
      readFileSync(join(__dirname, "../../resources/apple", file))),
    true, environment, bundleId, Number(appleAppId.value()),
  );

export const verifyAppleNotification = async (payload: string) => {
  try {
    return await appleVerifier(Environment.PRODUCTION)
      .verifyAndDecodeNotification(payload);
  } catch {
    return appleVerifier(Environment.SANDBOX)
      .verifyAndDecodeNotification(payload);
  }
};

export const verifyApplePurchase = async (
  evidence: string, transactionId?: string, sandbox = false,
): Promise<VerifiedSubscription> => {
  let environment = sandbox ? Environment.SANDBOX : Environment.PRODUCTION;
  if (evidence) {
    // The environment supplied by the client is never trusted.
    let decoded;
    try {
      decoded = await appleVerifier(Environment.PRODUCTION)
        .verifyAndDecodeTransaction(evidence);
      environment = Environment.PRODUCTION;
    } catch {
      decoded = await appleVerifier(Environment.SANDBOX)
        .verifyAndDecodeTransaction(evidence);
      environment = Environment.SANDBOX;
    }
    transactionId = decoded.originalTransactionId;
  }
  if (!transactionId) throw new HttpsError("invalid-argument", "Missing proof");
  const observedAt = Date.now();
  const client = new AppStoreServerAPIClient(
    appleKey.value(), appleKeyId.value(), appleIssuerId.value(),
    bundleId, environment,
  );
  // Reconcile with current store status: an old, valid JWS can be refunded or
  // replaced after signing and must not re-grant revoked access.
  const response = await client.getAllSubscriptionStatuses(transactionId);
  for (const group of response.data ?? []) {
    for (const last of group.lastTransactions ?? []) {
      if (last.originalTransactionId !== transactionId ||
          !last.signedTransactionInfo) continue;
      const verifier = appleVerifier(environment);
      const tx = await verifier.verifyAndDecodeTransaction(
        last.signedTransactionInfo,
      );
      const renewal = last.signedRenewalInfo ?
        await verifier.verifyAndDecodeRenewalInfo(last.signedRenewalInfo) :
        null;
      const tier = tx.productId === "com.smartreceipt.premium.monthly" ?
        "monthly" : tx.productId === "com.smartreceipt.premium.yearly" ?
          "yearly" : undefined;
      if (!tier || !tx.expiresDate || !tx.originalTransactionId) {
        throw new HttpsError("failed-precondition", "Unknown subscription");
      }
      const expiresAt = last.status === 4 ?
        renewal?.gracePeriodExpiresDate ?? tx.expiresDate : tx.expiresDate;
      return {
        source: "apple", id: tx.originalTransactionId,
        productId: tx.productId as string, tier, expiresAt, environment,
        active: [1, 4].includes(last.status ?? 0) &&
          !tx.revocationDate && !tx.isUpgraded,
        accountToken: tx.appAccountToken?.toLowerCase(), observedAt,
      };
    }
  }
  throw new HttpsError("not-found", "Subscription not found");
};
