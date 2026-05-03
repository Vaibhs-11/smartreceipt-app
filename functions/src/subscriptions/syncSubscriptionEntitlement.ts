import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

const sanitizedString = (value: unknown): string | undefined => {
  if (typeof value !== "string") return undefined;
  return value.slice(0, 64);
};

export const syncSubscriptionEntitlement = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  logger.warn("Client subscription entitlement sync disabled", {
    uid,
    requestedSource: sanitizedString(request.data?.source),
    requestedStatus: sanitizedString(request.data?.status),
    requestedTier: sanitizedString(request.data?.tier),
    timestamp: new Date().toISOString(),
  });

  return {
    accepted: false,
    reason: "client_entitlement_sync_disabled",
  };
});
