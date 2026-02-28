import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as admin from "firebase-admin";

const TRIAL_DAYS = 7;
const MILLIS_PER_DAY = 24 * 60 * 60 * 1000;

type AccountStatus = "free" | "trial" | "paid";

interface UserDoc {
  accountStatus?: AccountStatus;
  trialUsed?: boolean;
}

export const startTrial = onCall(async (request) => {
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const firestore = admin.firestore();
  const userRef = firestore.collection("users").doc(uid);

  const nowDate = new Date();
  const trialStartedAt = admin.firestore.Timestamp.fromDate(nowDate);
  const trialEndsAt = admin.firestore.Timestamp.fromDate(
    new Date(nowDate.getTime() + TRIAL_DAYS * MILLIS_PER_DAY)
  );

  return firestore.runTransaction(async (tx) => {
    const userSnap = await tx.get(userRef);
    if (!userSnap.exists) {
      tx.set(
        userRef,
        {
          accountStatus: "trial",
          trialStartedAt,
          trialEndsAt,
          trialUsed: true,
          subscriptionTier: "free",
        },
        {merge: true}
      );
      return {
        status: "started",
        trialEndsAt: trialEndsAt.toMillis(),
      };
    }

    const userData = (userSnap.data() ?? {}) as UserDoc;
    const trialUsed = userData.trialUsed === true;
    const accountStatus = (userData.accountStatus ?? "free").toLowerCase();

    if (trialUsed) {
      throw new HttpsError("failed-precondition", "Trial already used.");
    }

    if (accountStatus === "trial" || accountStatus === "paid") {
      throw new HttpsError(
        "failed-precondition",
        "Trial cannot be started for the current account state."
      );
    }

    tx.set(
      userRef,
      {
        accountStatus: "trial",
        trialStartedAt,
        trialEndsAt,
        trialUsed: true,
      },
      {merge: true}
    );

    return {
      status: "started",
      trialEndsAt: trialEndsAt.toMillis(),
    };
  });
});
