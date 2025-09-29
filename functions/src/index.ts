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

export const visionOcr = onCall(async (request) => {
  // Ensure the user is authenticated.
  const uid = request.auth?.uid;
  if (!uid) {
    throw new HttpsError("unauthenticated", "User must be authenticated");
  }

  const {path, imageBase64, imageUrl, gcsUri} = request.data || {};

  if (!path && !imageBase64 && !imageUrl && !gcsUri) {
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
      // Case 1: Direct GCS URI passed in
      logger.info(`Using provided GCS URI: ${gcsUri}`);
      visionRequest = {image: {source: {imageUri: gcsUri}}};
    } else if (path) {
      const isPdf = path.toLowerCase().endsWith(".pdf");
      if (isPdf) {
        // PDFs require a GCS URI
        const bucketName = admin.storage().bucket().name;
        const gcsUriFromPath = `gs://${bucketName}/${path}`;
        logger.info(`PDF to Vision API with GCS URI: ${gcsUriFromPath}`);
        visionRequest = {image: {source: {imageUri: gcsUriFromPath}}};
      } else {
        // Images from Firebase Storage (download as buffer)
        const bucket = admin.storage().bucket();
        const file = bucket.file(path);
        const [buffer] = await file.download();
        visionRequest = {image: {content: buffer}};
      }
    } else if (imageBase64) {
      // Case 3: Direct base64 content from client
      const buffer = Buffer.from(imageBase64, "base64");
      visionRequest = {image: {content: buffer}};
    } else if (imageUrl) {
      // Case 4: Remote image URL
      visionRequest = {image: {source: {imageUri: imageUrl}}};
    }

    // Call Vision API
    if (!visionRequest) {
      throw new HttpsError("invalid-argument", "No valid image provided");
    }
    const [result] = await client.documentTextDetection(visionRequest);


    logger.info("Full Vision API response", {visionResult: result});

    const text = result.fullTextAnnotation?.text || "";
    const locale =
      result.fullTextAnnotation?.pages?.[0]?.property?.detectedLanguages?.[0]
        ?.languageCode || null;

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
