import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import * as logger from "firebase-functions/logger";
import {ImageAnnotatorClient} from "@google-cloud/vision";
import * as admin from "firebase-admin";
import sharp from "sharp";
import * as path from "path";
import * as fs from "fs/promises";
export {startTrial} from "./subscriptions/startTrial";
export {
  syncSubscriptionEntitlement,
} from "./subscriptions/syncSubscriptionEntitlement";

// ----------------------
// Initialization
// ----------------------

admin.initializeApp();
const client = new ImageAnnotatorClient();

setGlobalOptions({maxInstances: 10});

type AccountStatus = "free" | "trial" | "paid";
type SubscriptionTier = "free" | "monthly" | "yearly";
type SubscriptionStatus = "active" | "expired" | "none";

interface UserDoc {
  accountStatus?: AccountStatus;
  trialEndsAt?: admin.firestore.Timestamp;
  subscriptionEndsAt?: admin.firestore.Timestamp;
  trialDowngradeRequired?: boolean;
  subscriptionTier?: SubscriptionTier;
  subscriptionStatus?: SubscriptionStatus;
}

interface AppConfigDoc {
  freeReceiptLimit: number;
  premiumReceiptLimit: number;
  enablePaidTiers: boolean;
}

const firestore = admin.firestore();

const configRef = firestore.collection("config").doc("app");

const fetchAppConfig = async (): Promise<AppConfigDoc> => {
  const snap = await configRef.get();
  if (!snap.exists) {
    throw new HttpsError("failed-precondition", "App config missing");
  }
  const data = snap.data() ?? {};
  const freeLimit = data["freeReceiptLimit"];
  if (typeof freeLimit !== "number") {
    throw new HttpsError(
      "failed-precondition",
      "App config missing freeReceiptLimit"
    );
  }
  const premiumLimit =
    typeof data["premiumReceiptLimit"] === "number" ?
      data["premiumReceiptLimit"] :
      -1;
  const enablePaidTiers =
    typeof data["enablePaidTiers"] === "boolean" ?
      data["enablePaidTiers"] :
      true;
  return {
    freeReceiptLimit: freeLimit,
    premiumReceiptLimit: premiumLimit,
    enablePaidTiers,
  };
};

// ----------------------
// Existing Vision OCR Callable (UNCHANGED)
// ----------------------

export const visionOcr = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const {path: imagePath, imageBase64, imageUrl, gcsUri} =
    request.data || {};

  if (!imagePath && !imageBase64 && !imageUrl && !gcsUri) {
    throw new HttpsError(
      "invalid-argument",
      "Must provide either 'path', 'imageBase64', 'imageUrl', or 'gcsUri'."
    );
  }

  try {
    let visionRequest:
      | {image: {source: {imageUri: string}}}
      | {image: {content: Buffer}}
      | null = null;

    if (gcsUri) {
      visionRequest = {image: {source: {imageUri: gcsUri}}};
    } else if (imagePath) {
      const isPdf = imagePath.toLowerCase().endsWith(".pdf");
      if (isPdf) {
        const bucketName = admin.storage().bucket().name;
        visionRequest = {
          image: {source: {imageUri: `gs://${bucketName}/${imagePath}`}},
        };
      } else {
        const file = admin.storage().bucket().file(imagePath);
        const [buffer] = await file.download();
        visionRequest = {image: {content: buffer}};
      }
    } else if (imageBase64) {
      visionRequest = {
        image: {content: Buffer.from(imageBase64, "base64")},
      };
    } else if (imageUrl) {
      visionRequest = {image: {source: {imageUri: imageUrl}}};
    }

    if (!visionRequest) {
      throw new HttpsError("invalid-argument", "No valid image provided");
    }

    const [result] = await client.documentTextDetection(visionRequest);

    const text = result.fullTextAnnotation?.text || "";
    const locale =
      result.fullTextAnnotation?.pages?.[0]?.property
        ?.detectedLanguages?.[0]?.languageCode || null;

    return {text, locale};
  } catch (error) {
    logger.error("Vision API failed", {error});
    throw new HttpsError(
      "internal",
      "Failed to process receipt image with Vision API",
      error as Error
    );
  }
});

// ----------------------
// NEW: Receipt Image Processing (Firestore Trigger)
// ----------------------

export const processReceiptImage = onDocumentCreated(
  "users/{uid}/receipts/{receiptId}",
  async (event) => {
    const snap = event.data;
    if (!snap) {
      return;
    }

    const data = snap.data();
    const {uid, receiptId} = event.params;

    const originalImagePath = data.originalImagePath;
    const processedImagePath = data.processedImagePath;
    const status = data.imageProcessingStatus;

    // -------- Guard clauses --------
    if (!originalImagePath) {
      logger.info("No original image; skipping", {receiptId});
      return;
    }

    if (processedImagePath) {
      logger.info("Already processed; skipping", {receiptId});
      return;
    }

    if (status !== "pending") {
      logger.info("Status not pending; skipping", {receiptId, status});
      return;
    }

    logger.info("Starting receipt image processing", {uid, receiptId});

    const bucket = admin.storage().bucket();

    const storagePath = originalImagePath.startsWith("http") ?
      decodeURIComponent(
        originalImagePath.split("/o/")[1].split("?")[0]
      ) :
      originalImagePath;

    const tmpInput = path.join("/tmp", `${receiptId}-original`);
    const tmpOutput = path.join("/tmp", `${receiptId}-processed.jpg`);

    try {
      await bucket.file(storagePath).download({destination: tmpInput});

      await sharp(tmpInput)
        .rotate()
        .resize({width: 2000, withoutEnlargement: true})
        .sharpen()
        .jpeg({quality: 88})
        .toFile(tmpOutput);

      const processedStoragePath =
        `receipts/${uid}/${receiptId}/processed.jpg`;

      await bucket.upload(tmpOutput, {
        destination: processedStoragePath,
        contentType: "image/jpeg",
      });

      await snap.ref.update({
        processedImagePath: processedStoragePath,
        imageProcessingStatus: "completed",
      });

      logger.info("Receipt image processed successfully", {receiptId});
    } catch (error) {
      logger.error("Receipt image processing failed", {receiptId, error});

      await snap.ref.update({
        imageProcessingStatus: "failed",
      });
    } finally {
      try {
        await fs.unlink(tmpInput);
      } catch (e) {
        logger.debug("Temp input cleanup skipped");
      }

      try {
        await fs.unlink(tmpOutput);
      } catch (e) {
        logger.debug("Temp output cleanup skipped");
      }
    }
  }
);

// ----------------------
// Account helpers
// ----------------------

const asAccountStatus = (raw?: string | null): AccountStatus => {
  switch ((raw ?? "").toLowerCase()) {
  case "trial":
    return "trial";
  case "paid":
    return "paid";
  case "free":
  default:
    return "free";
  }
};

const isExpired = (user: UserDoc, now: Date): boolean => {
  const account = asAccountStatus(user.accountStatus || "free");
  if (account === "trial" && user.trialEndsAt) {
    return now > user.trialEndsAt.toDate();
  }
  if (user.subscriptionStatus === "expired") return true;
  return false;
};

const canAddReceipt = (
  user: UserDoc,
  receiptCount: number,
  now: Date,
  config: AppConfigDoc
): boolean => {
  const status = asAccountStatus(user.accountStatus || "free");
  if (user.trialDowngradeRequired) return false;
  if (config.enablePaidTiers &&
    user.subscriptionStatus === "active" &&
    user.subscriptionTier && user.subscriptionTier !== "free") {
    return true;
  }
  if (config.enablePaidTiers &&
    status === "trial" && (!user.trialEndsAt ||
    now < user.trialEndsAt.toDate())) {
    if (config.premiumReceiptLimit === -1) return true;
    return receiptCount < config.premiumReceiptLimit;
  }
  return receiptCount < config.freeReceiptLimit;
};

const resolveStoragePath = (
  value: unknown,
  uid: string,
  bucketName: string
): string | null => {
  if (!value || typeof value !== "string") return null;
  const pathStr = value as string;
  if (pathStr.startsWith("gs://")) {
    const withoutScheme = pathStr.replace(`gs://${bucketName}/`, "");
    if (withoutScheme.startsWith(`receipts/${uid}`)) {
      return withoutScheme;
    }
    return null;
  }

  if (pathStr.startsWith("http")) {
    try {
      const decoded = decodeURIComponent(pathStr.split("/o/")[1].split("?")[0]);
      if (decoded.startsWith(`receipts/${uid}`)) {
        return decoded;
      }
    } catch (e) {
      logger.warn("Failed to parse storage URL", {value, e});
    }
    return null;
  }

  if (pathStr.startsWith(`receipts/${uid}`)) return pathStr;
  return null;
};

// ----------------------
// NEW: Downgrade callable
// ----------------------

export const finalizeDowngradeToFree = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const appConfig = await fetchAppConfig();
  const freeLimit = appConfig.freeReceiptLimit;

  const keepIds = request.data?.keepReceiptIds as unknown;
  if (!Array.isArray(keepIds) || keepIds.length !== freeLimit) {
    throw new HttpsError(
      "invalid-argument",
      `keepReceiptIds must be an array of exactly ${freeLimit} receipt IDs`
    );
  }

  const keep = new Set(
    (keepIds as unknown[]).map((id) => String(id))
  );
  if (keep.size !== freeLimit) {
    throw new HttpsError(
      "invalid-argument",
      "keepReceiptIds must be unique"
    );
  }

  const userRef = firestore.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("failed-precondition", "User record not found");
  }

  const userData = userSnap.data() as UserDoc;
  const now = new Date();
  const expired = isExpired(userData, now);
  if (!userData.trialDowngradeRequired && !expired) {
    throw new HttpsError(
      "failed-precondition",
      "Downgrade is not required"
    );
  }

  const receiptsSnap = await userRef.collection("receipts").get();
  const allReceipts = receiptsSnap.docs;
  if (allReceipts.length < keep.size) {
    throw new HttpsError(
      "failed-precondition",
      "Selected receipts are not valid"
    );
  }

  for (const id of keep) {
    const exists = allReceipts.find((doc) => doc.id === id);
    if (!exists) {
      throw new HttpsError(
        "failed-precondition",
        "Selected receipts are not valid"
      );
    }
  }

  const bucket = admin.storage().bucket();
  for (const doc of allReceipts) {
    if (keep.has(doc.id)) continue;
    const data = doc.data();
    const paths = [
      data.originalImagePath,
      data.processedImagePath,
      data.imagePath,
      data.fileUrl,
    ];
    for (const p of paths) {
      const resolved = resolveStoragePath(p, uid, bucket.name);
      if (resolved) {
        try {
          await bucket.file(resolved).delete({ignoreNotFound: true});
        } catch (e) {
          logger.warn("Failed to delete storage file", {resolved, e});
        }
      }
    }
    await doc.ref.delete();
  }

  await userRef.set(
    {
      accountStatus: "free",
      trialDowngradeRequired: false,
      subscriptionTier: "free",
      subscriptionStatus: userData.subscriptionStatus ?? "none",
    },
    {merge: true}
  );

  return {
    kept: Array.from(keep),
    deleted: allReceipts.length - keep.size,
  };
});

// ----------------------
// NEW: Receipt creation gate
// ----------------------

export const createReceipt = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const receipt = request.data?.receipt as Record<string, unknown> | undefined;
  const receiptId = request.data?.receiptId as string | undefined;
  if (!receipt || !receiptId) {
    throw new HttpsError(
      "invalid-argument",
      "Missing receipt payload or receiptId"
    );
  }

  const userRef = firestore.collection("users").doc(uid);
  const userSnap = await userRef.get();
  if (!userSnap.exists) {
    throw new HttpsError("failed-precondition", "User not found");
  }

  const userData = userSnap.data() as UserDoc;
  const now = new Date();
  const appConfig = await fetchAppConfig();

  const dateValue = receipt["date"];
  let parsedDate: Date | null = null;
  if (typeof dateValue === "string") {
    parsedDate = new Date(dateValue);
  } else if (dateValue && typeof dateValue === "object" &&
    "seconds" in (dateValue as Record<string, unknown>)) {
    const seconds = Number(
      (dateValue as Record<string, unknown>)["seconds"]
    );
    parsedDate = new Date(seconds * 1000);
  }

  const expiryValue = receipt["expiryDate"];
  let parsedExpiry: Date | null = null;
  if (typeof expiryValue === "string") {
    parsedExpiry = new Date(expiryValue);
  }

  const payload: Record<string, unknown> = {
    ...receipt,
    date: parsedDate ?
      admin.firestore.Timestamp.fromDate(parsedDate) :
      admin.firestore.Timestamp.fromDate(new Date()),
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (parsedExpiry) {
    payload["expiryDate"] = admin.firestore.Timestamp.fromDate(parsedExpiry);
  }

  const receiptRef = userRef.collection("receipts").doc(receiptId);
  await firestore.runTransaction(async (tx) => {
    const receiptsSnap = await tx.get(userRef.collection("receipts"));
    const currentCount = receiptsSnap.size;
    if (!canAddReceipt(userData, currentCount, now, appConfig)) {
      throw new HttpsError(
        "failed-precondition",
        "Receipt limit reached",
        {reason: "FREE_LIMIT_REACHED"}
      );
    }
    tx.set(receiptRef, payload);
  });
  return {ok: true};
});

// ----------------------
// NEW: Account deletion callable
// ----------------------

export const deleteAccount = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  try {
    const userRef = firestore.collection("users").doc(uid);
    await firestore.recursiveDelete(userRef);

    try {
      await admin.auth().deleteUser(uid);
    } catch (error) {
      const err = error as {code?: string; message?: string};
      if (err.code !== "auth/user-not-found") {
        throw error;
      }
    }

    return {success: true};
  } catch (error) {
    logger.error("Account deletion failed", {uid, error});
    throw new HttpsError("internal", "Account deletion failed");
  }
});
