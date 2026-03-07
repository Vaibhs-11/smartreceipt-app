import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

interface ReceiptEnrichmentTaskPayload {
  userId: string;
  receiptId: string;
}

const RECEIPT_ENRICHMENT_TASK_ID_PREFIX = "receipt-enrichment";

export const enqueueReceiptEnrichment = async (
  userId: string,
  receiptId: string
): Promise<void> => {
  const payload: ReceiptEnrichmentTaskPayload = {
    userId,
    receiptId,
  };

  const queue = admin.functions().taskQueue("processReceiptEnrichment");

  const taskId = `${RECEIPT_ENRICHMENT_TASK_ID_PREFIX}-${userId}-${receiptId}`;

  try {
    await queue.enqueue(payload, {id: taskId});
    logger.info("Queued receipt enrichment task", {
      userId,
      receiptId,
      taskId,
    });
  } catch (error: unknown) {
    const taskError = error as {code?: string; message?: string};
    if (
      taskError.code === "functions/task-already-exists" ||
      (typeof taskError.message === "string" &&
        taskError.message.includes("already exists"))
    ) {
      logger.info("Receipt enrichment task already exists; skipping enqueue", {
        userId,
        receiptId,
        taskId,
      });
      return;
    }

    logger.error("Failed to enqueue receipt enrichment task", {
      userId,
      receiptId,
      error,
    });
    throw error;
  }
};
