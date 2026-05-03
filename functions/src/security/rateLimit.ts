import {HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const RATE_LIMIT_COLLECTION = "system_rate_limits";
const DEFAULT_WINDOW_MS = 60 * 60 * 1000;

interface RateLimitOptions {
  firestore: admin.firestore.Firestore;
  uid: string;
  functionName: string;
  maxCalls: number;
  windowMs?: number;
}

interface RateLimitDoc {
  count?: unknown;
  windowStart?: unknown;
}

export const getPayloadSizeBytes = (value: unknown): number => {
  try {
    return Buffer.byteLength(JSON.stringify(value ?? null), "utf8");
  } catch (_) {
    return Number.MAX_SAFE_INTEGER;
  }
};

export const assertPayloadSize = (
  value: unknown,
  maxBytes: number
): void => {
  if (getPayloadSizeBytes(value) > maxBytes) {
    throw new HttpsError("invalid-argument", "Request payload is too large");
  }
};

export const assertUserRateLimit = async ({
  firestore,
  uid,
  functionName,
  maxCalls,
  windowMs = DEFAULT_WINDOW_MS,
}: RateLimitOptions): Promise<void> => {
  const nowMillis = Date.now();
  const rateLimitRef = firestore
    .collection(RATE_LIMIT_COLLECTION)
    .doc(uid)
    .collection("functions")
    .doc(functionName);

  await firestore.runTransaction(async (tx) => {
    const snap = await tx.get(rateLimitRef);
    const data = snap.data() as RateLimitDoc | undefined;
    const rawWindowStart = data?.windowStart;
    const windowStartMillis =
      rawWindowStart instanceof admin.firestore.Timestamp ?
        rawWindowStart.toMillis() :
        0;
    const currentCount =
      typeof data?.count === "number" && Number.isFinite(data.count) ?
        data.count :
        0;
    const shouldReset =
      !snap.exists || nowMillis - windowStartMillis >= windowMs;

    const nextCount = shouldReset ? 1 : currentCount + 1;
    if (nextCount > maxCalls) {
      throw new HttpsError(
        "resource-exhausted",
        "Too many requests. Please try again later."
      );
    }

    tx.set(
      rateLimitRef,
      {
        count: nextCount,
        maxCalls,
        windowMs,
        windowStart: shouldReset ?
          admin.firestore.Timestamp.fromMillis(nowMillis) :
          rawWindowStart,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      {merge: true}
    );
  });
};
