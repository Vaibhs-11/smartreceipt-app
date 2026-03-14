import * as admin from "firebase-admin";
import {getFunctions} from "firebase-admin/functions";

admin.initializeApp();

const firestore = admin.firestore();

// Update these before running
const QUEUE_FUNCTION_NAME = "processReceiptEnrichment";
const TARGET_ENRICHMENT_VERSION = 2;

// IMPORTANT: must match your project
const SERVICE_ACCOUNT_EMAIL =
  "firebase-adminsdk-fbsvc@smartreceipt-8faff.iam.gserviceaccount.com";

// Safety controls
const DRY_RUN = false; // set to false when ready
const BATCH_SIZE = 25;
const PAUSE_MS = 1500;
const MAX_RECEIPTS = 500;

/**
 * Sleep for the specified duration.
 * @param {number} ms - Delay in milliseconds.
 * @return {Promise<void>} Promise that resolves after the delay.
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Processes receipts and enqueues those needing enrichment updates.
 */
async function main() {
  const queue = getFunctions().taskQueue(QUEUE_FUNCTION_NAME);

  let scanned = 0;
  let matched = 0;
  let queued = 0;

  const usersSnap = await firestore.collection("users").get();

  for (const userDoc of usersSnap.docs) {
    const userId = userDoc.id;
    const userData = userDoc.data() ?? {};

    // 🔒 PREMIUM USER CHECK
    const subscriptionStatus = userData["subscriptionStatus"];
    const trialStatus = userData["accountStatus"];
    if (subscriptionStatus !== "active" && trialStatus !== "trial") {
      continue;
    }

    const receiptsSnap = await firestore
      .collection("users")
      .doc(userId)
      .collection("receipts")
      .get();

    for (const receiptDoc of receiptsSnap.docs) {
      scanned++;

      const data = receiptDoc.data() ?? {};
      const enrichment =
        (data["enrichment"] as
          | {
              status?: unknown;
              version?: unknown;
            }
          | undefined) ?? {};

      const currentVersion =
        typeof enrichment.version === "number" ? enrichment.version : 0;

      if (currentVersion >= TARGET_ENRICHMENT_VERSION) {
        continue;
      }

      matched++;

      if (DRY_RUN) {
        console.log(
          `[DRY RUN] Would enqueue receipt ${receiptDoc.id}` +
            ` for user ${userId} ` +
            `(current version: ${currentVersion})`
        );
      } else {
        await queue.enqueue(
          {
            userId,
            receiptId: receiptDoc.id,
          },
          {
            oidcToken: {
              serviceAccountEmail: SERVICE_ACCOUNT_EMAIL,
            },
          }
        );

        queued++;

        console.log(
          `Queued receipt ${receiptDoc.id} for user ${userId} ` +
            `(current version: ${currentVersion})`
        );

        if (queued % BATCH_SIZE === 0) {
          console.log(`Paused after ${queued} queued tasks...`);
          await sleep(PAUSE_MS);
        }

        if (queued >= MAX_RECEIPTS) {
          console.log(`Reached MAX_RECEIPTS=${MAX_RECEIPTS}. Stopping.`);
          console.log({scanned, matched, queued});
          return;
        }
      }
    }
  }

  console.log("Done.");
  console.log({scanned, matched, queued, dryRun: DRY_RUN});
}

main().catch((error) => {
  console.error("Requeue script failed:", error);
  process.exit(1);
});
