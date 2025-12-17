import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onDocumentCreated} from "firebase-functions/v2/firestore";
import {setGlobalOptions} from "firebase-functions/v2";
import * as logger from "firebase-functions/logger";
import {ImageAnnotatorClient} from "@google-cloud/vision";
import * as admin from "firebase-admin";
import sharp from "sharp";
import * as path from "path";
import * as fs from "fs/promises";

// ----------------------
// Initialization
// ----------------------

admin.initializeApp();
const client = new ImageAnnotatorClient();

setGlobalOptions({maxInstances: 10});

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
