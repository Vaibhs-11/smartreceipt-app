/**
 * Import function triggers from their respective submodules:
 *
 * import {onCall} from "firebase-functions/v2/https";
 * import {onDocumentWritten} from "firebase-functions/v2/firestore";
 *
 * See a full list of supported triggers at https://firebase.google.com/docs/functions
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {setGlobalOptions} from "firebase-functions/v2";
import * as logger from "firebase-functions/logger";
import {ImageAnnotatorClient} from "@google-cloud/vision";
import * as admin from "firebase-admin";

// Initialize Firebase Admin SDK
admin.initializeApp();

// Initialize Vision AI Client
const client = new ImageAnnotatorClient();

// Set global options for all functions
setGlobalOptions({maxInstances: 10});

export const parseReceipt = onCall(async (request) => {
  // Ensure the user is authenticated.
  if (!request.auth) {
    throw new HttpsError(
      "unauthenticated",
      "The function must be called while authenticated.",
    );
  }

  const imageUrl = request.data.imageUrl;
  if (typeof imageUrl !== "string" || !imageUrl) {
    throw new HttpsError(
      "invalid-argument",
      "The function must be called with a valid 'imageUrl'.",
    );
  }

  logger.info(`Parsing receipt from URL: ${imageUrl}`, {uid: request.auth.uid});

  try {
    const [result] = await client.textDetection(imageUrl);
    const detections = result.textAnnotations;
    return {text: detections?.[0]?.description ?? ""};
  } catch (error) {
    logger.error("Error calling Vision API", {error, imageUrl});
    throw new HttpsError(
      "internal",
      "Failed to process receipt image with Vision API.",
      error,
    );
  }
});
