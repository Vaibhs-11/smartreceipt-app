import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {enqueueReceiptEnrichment} from "./enqueueReceiptEnrichment";

const isEnrichmentInProgressOrDone = (
  data: admin.firestore.DocumentData
): boolean => {
  const enrichment = data["enrichment"];
  if (!enrichment || typeof enrichment !== "object") {
    return false;
  }

  const status = (enrichment as {status?: unknown})["status"];
  return status === "processing" || status === "completed";
};

export const enqueueEnrichmentForExistingReceipts = async (
  uid: string,
): Promise<void> => {
  const receiptsSnapshot = await admin
    .firestore()
    .collection("users")
    .doc(uid)
    .collection("receipts")
    .get();

  let enqueued = 0;
  let skipped = 0;
  let failed = 0;

  for (const doc of receiptsSnapshot.docs) {
    const data = doc.data();

    if (isEnrichmentInProgressOrDone(data)) {
      skipped += 1;
      continue;
    }

    try {
      await enqueueReceiptEnrichment(uid, doc.id);
      enqueued += 1;
    } catch (error) {
      failed += 1;
      logger.error("Failed to enqueue backfill receipt enrichment", {
        uid,
        receiptId: doc.id,
        error,
      });
    }
  }

  logger.info("Backfilled receipt enrichment for existing receipts", {
    uid,
    totalReceipts: receiptsSnapshot.size,
    enqueued,
    skipped,
    failed,
  });
};
