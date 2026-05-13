import * as admin from "firebase-admin";
import {getFunctions} from "firebase-admin/functions";

const PROJECT_ID = process.env.GOOGLE_CLOUD_PROJECT || "smartreceipt-8faff";
const ADMIN_SERVICE_ACCOUNT_ID =
  process.env.FIREBASE_SERVICE_ACCOUNT_ID ||
  "smartreceipt-8faff@appspot.gserviceaccount.com";

// Uses Application Default Credentials locally. Before running:
// gcloud auth application-default login
// gcloud auth application-default set-quota-project smartreceipt-8faff
admin.initializeApp({
  projectId: PROJECT_ID,
  serviceAccountId: ADMIN_SERVICE_ACCOUNT_ID,
});

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
  console.error(
    [
      "Local ADC setup:",
      "1. gcloud auth application-default login",
      "2. gcloud auth application-default set-quota-project smartreceipt-8faff",
      "3. FIREBASE_SERVICE_ACCOUNT_ID=" +
        "<deployed-functions-service-account-email>",
    ].join("\n")
  );
  process.exit(1);
});
