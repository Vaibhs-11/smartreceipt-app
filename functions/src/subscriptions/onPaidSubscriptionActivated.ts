import {onDocumentWritten} from "firebase-functions/v2/firestore";
import {hasLivePaidAccess} from "./subscriptionPolicy";
import {
  enqueueEnrichmentForExistingReceipts,
} from "../enrichment/backfillExistingReceiptEnrichment";

// Independent of purchase acknowledgement: a queue outage must not stop paid
// access. Repeated deliveries skip enrichment already processing/completed.
export const onPaidSubscriptionActivated = onDocumentWritten(
  {document: "users/{uid}", retry: true}, async (event) => {
    const change = event.data;
    if (!change?.after.exists) return;
    const now = Date.now();
    if (!hasLivePaidAccess(change.after.data() ?? {}, now) ||
        hasLivePaidAccess(change.before.data() ?? {}, now)) return;
    const latest = await change.after.ref.get();
    if (!hasLivePaidAccess(latest.data() ?? {}, Date.now())) return;
    await enqueueEnrichmentForExistingReceipts(event.params.uid, true);
  },
);
