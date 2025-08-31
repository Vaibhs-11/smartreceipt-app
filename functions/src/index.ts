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
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const path = request.data.path;
  if (typeof path !== "string" || !path) {
    throw new HttpsError(
      "invalid-argument",
      "The function must be called with a valid 'path' parameter.",
    );
  }

  logger.info(`Parsing receipt from path: ${path}`, {uid});

  const isPdf = path.toLowerCase().endsWith(".pdf");

  try {
    // The request to the Vision API needs to be structured differently
    // for PDFs vs. images when processing online.
    let visionRequest;
    if (isPdf) {
      // For PDFs, Vision API needs the GCS URI.
      const bucketName = admin.storage().bucket().name;
      const gcsUri = `gs://${bucketName}/${path}`;
      logger.info(`Sending PDF to Vision API with GCS URI: ${gcsUri}`);
      visionRequest = {image: {source: {imageUri: gcsUri}}};
    } else {
      // For images, we can send the byte content.
      const bucket = admin.storage().bucket();
      const file = bucket.file(path);
      const [buffer] = await file.download();
      visionRequest = {image: {content: buffer}};
    }

    const [result] = await client.documentTextDetection(visionRequest);
    // Log the full JSON response from the Vision API for debugging.
    // This will appear in your Cloud Function logs in the Firebase Console.
    logger.info("Full Vision API response:", {visionResult: result});

    const text = result.fullTextAnnotation?.text || "";

    return {
      text,
      locale:
        result.fullTextAnnotation?.pages?.[0]?.property?.detectedLanguages?.[0]
          ?.languageCode || null,
    };
  } catch (error) {
    logger.error("Vision API failed", {error, path});
    throw new HttpsError(
      "internal",
      "Failed to process receipt image with Vision API",
      error as Error
    );
  }
});
