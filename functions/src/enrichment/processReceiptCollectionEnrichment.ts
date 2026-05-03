import {onTaskDispatched} from "firebase-functions/v2/tasks";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import {logEvent} from "../analytics/log_event";
import {
  assertPayloadSize,
  assertUserRateLimit,
} from "../security/rateLimit";

const CURRENT_COLLECTION_ENRICHMENT_VERSION = 1;
const OPENAI_TIMEOUT_MS = 45000;
const MAX_COLLECTION_ENRICHMENT_TASK_PAYLOAD_BYTES = 8 * 1024;
const COLLECTION_ENRICHMENT_MAX_CALLS_PER_HOUR = 50;

const FALLBACK_COLLECTION_CATEGORIES = [
  "Travel",
  "Local Transport",
  "Accommodation",
  "Food & Drinks",
  "Activities",
  "Shopping",
  "Misc",
];

interface ReceiptCollectionEnrichmentTaskPayload {
  userId?: unknown;
  receiptId?: unknown;
  collectionId?: unknown;
}

interface ReceiptCollectionSuggestion {
  index: unknown;
  category: unknown;
}

interface CollectionEnrichmentResponse {
  items?: unknown;
}

interface GPTChoice {
  message?: {
    content?: string;
  };
}

interface GPTCompletion {
  choices?: GPTChoice[];
}

const parseStringArray = (value: unknown): string[] => {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
};

const parseCollectionEnrichmentResponse = (
  raw: string
): {items: ReceiptCollectionSuggestion[]} => {
  const trimmed = raw.trim();
  const fencedJsonMatch = trimmed.match(/```json\s*([\s\S]*?)\s*```/i);
  const jsonText = fencedJsonMatch ? fencedJsonMatch[1] : trimmed;

  const parsed = JSON.parse(jsonText) as CollectionEnrichmentResponse;
  if (!Array.isArray(parsed.items)) {
    throw new Error("OpenAI response missing items array.");
  }

  return {items: parsed.items as ReceiptCollectionSuggestion[]};
};

const validateAndMapSuggestions = (
  suggestions: ReceiptCollectionSuggestion[],
  itemCount: number,
  allowedCategories: string[]
): ReceiptCollectionSuggestion[] => {
  const normalizedAllowed = new Set(allowedCategories);
  const validSuggestions = new Map<number, ReceiptCollectionSuggestion>();

  for (const suggestion of suggestions) {
    const index = suggestion.index;

    if (typeof index !== "number" || !Number.isInteger(index) || index < 0) {
      throw new Error(`Invalid suggestion index: ${String(index)}.`);
    }
    if (index >= itemCount) {
      throw new Error(`Suggestion index ${index} out of range.`);
    }

    if (typeof suggestion.category !== "string") {
      throw new Error(`Missing or invalid category for index ${index}.`);
    }
    if (!normalizedAllowed.has(suggestion.category)) {
      throw new Error(
        `Invalid category '${suggestion.category}' for index ${index}.`
      );
    }

    validSuggestions.set(index, suggestion);
  }

  return Array.from(validSuggestions.values());
};

const fetchCollectionCategories = async (
  firestore: admin.firestore.Firestore
): Promise<string[]> => {
  try {
    const doc = await firestore
      .collection("config")
      .doc("collection_categories")
      .get();
    if (!doc.exists) {
      return FALLBACK_COLLECTION_CATEGORIES;
    }

    const data = doc.data() ?? {};
    const categories = parseStringArray(data["categories"]);
    return categories.length > 0 ?
      categories :
      FALLBACK_COLLECTION_CATEGORIES;
  } catch (error) {
    logger.error(
      "Failed to load collection category config; using fallback categories.",
      {error}
    );
    return FALLBACK_COLLECTION_CATEGORIES;
  }
};

const parseOpenAIConfigFromResponse = async (payload: {
  collection_name: string;
  collection_type: string;
  merchant: string;
  allowed_categories: string[];
  items: Array<{name: string; price: number}>;
}): Promise<ReceiptCollectionSuggestion[]> => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("OpenAI API key is not configured.");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: "gpt-5-mini",
        response_format: {type: "json_object"},
        messages: [
          {
            role: "system",
            content:
              "You are a collection expense categorisation assistant.\n\n" +
              "Return ONLY valid JSON in format:\n" +
              "{\"items\":[{\"index\":number,\"category\":string}]}\n\n" +
              "Use ONLY categories from allowed_categories.\n\n" +
              "Classify each item independently.\n\n" +
              "Use collection context (trip/event name, type) when " +
              "helpful.\n\n" +
              "Categories:\n" +
              "- Travel: flights, trains, buses, intercity transport\n" +
              "- Local Transport: taxis, rideshare, fuel, parking\n" +
              "- Accommodation: hotels, Airbnb, stays\n" +
              "- Food & Drinks: restaurants, cafes, groceries\n" +
              "- Activities: tours, attractions, tickets, experiences\n" +
              "- Shopping: retail purchases, souvenirs\n" +
              "- Misc: anything else\n\n" +
              "If unsure, use 'Misc'.",
          },
          {
            role: "user",
            content: JSON.stringify(payload),
          },
        ],
      }),
    });

    if (!response.ok) {
      throw new Error(`OpenAI API failed: ${response.status}`);
    }

    const responseData = (await response.json()) as GPTCompletion;
    const content = responseData.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("OpenAI returned empty response content.");
    }

    const parsed = parseCollectionEnrichmentResponse(content);
    return parsed.items;
  } finally {
    clearTimeout(timeout);
  }
};

const parseReceiptItems = (
  data: admin.firestore.DocumentData
): Array<Record<string, unknown>> => {
  const rawItems = data["items"];
  if (!Array.isArray(rawItems)) {
    return [];
  }

  return rawItems.map((item) =>
    typeof item === "object" && item !== null ?
      (item as Record<string, unknown>) :
      {}
  );
};

const setCollectionEnrichmentStatus = async (
  receiptRef: admin.firestore.DocumentReference,
  status: string
) => {
  await receiptRef.update({"collectionEnrichment.status": status});
};

const getItemNameForEnrichment = (item: Record<string, unknown>): string => {
  if (
    typeof item["original_name"] === "string" &&
    item["original_name"].trim()
  ) {
    return item["original_name"];
  }

  if (typeof item["name"] === "string" && item["name"].trim()) {
    return item["name"];
  }

  return "";
};

const getItemPriceForEnrichment = (item: Record<string, unknown>): number => {
  return typeof item["price"] === "number" ? item["price"] : 0;
};

export const processReceiptCollectionEnrichment = onTaskDispatched(
  {
    secrets: ["OPENAI_API_KEY"],
  },
  async (request) => {
    assertPayloadSize(
      request.data,
      MAX_COLLECTION_ENRICHMENT_TASK_PAYLOAD_BYTES
    );

    const data = request.data as ReceiptCollectionEnrichmentTaskPayload;
    const userId = typeof data.userId === "string" ? data.userId : "";
    const receiptId = typeof data.receiptId === "string" ? data.receiptId : "";
    const collectionId =
      typeof data.collectionId === "string" ? data.collectionId : "";

    if (!userId || !receiptId || !collectionId) {
      logger.error("Invalid receipt collection enrichment task payload", {
        hasUserId: !!userId,
        hasReceiptId: !!receiptId,
        hasCollectionId: !!collectionId,
        taskId: request.id,
      });
      return;
    }

    logger.info("Processing receipt collection enrichment task", {
      userId,
      receiptId,
      collectionId,
      queueName: request.queueName,
      taskId: request.id,
    });

    const firestore = admin.firestore();
    await assertUserRateLimit({
      firestore,
      uid: userId,
      functionName: "processReceiptCollectionEnrichment",
      maxCalls: COLLECTION_ENRICHMENT_MAX_CALLS_PER_HOUR,
    });

    const receiptRef = firestore
      .collection("users")
      .doc(userId)
      .collection("receipts")
      .doc(receiptId);

    const receiptSnap = await receiptRef.get();
    if (!receiptSnap.exists) {
      logger.warn("Receipt not found for collection enrichment", {
        userId,
        receiptId,
        collectionId,
      });
      return;
    }

    const receiptData = receiptSnap.data() as admin.firestore.DocumentData;
    const currentCollectionId =
      typeof receiptData["collectionId"] === "string" ?
        receiptData["collectionId"] :
        null;

    if (currentCollectionId === null) {
      logger.info(
        "Receipt has no collectionId; skipping collection enrichment",
        {
          userId,
          receiptId,
        }
      );
      return;
    }

    if (currentCollectionId !== collectionId) {
      logger.info(
        "Receipt collectionId mismatch; skipping collection enrichment",
        {
          userId,
          receiptId,
          payloadCollectionId: collectionId,
          currentCollectionId,
        }
      );
      return;
    }

    const collectionEnrichment =
      ((receiptData["collectionEnrichment"] as
        | {
            status?: unknown;
            version?: unknown;
            collectionId?: unknown;
          }
        | undefined) ?? {});

    const status = collectionEnrichment.status;
    const version = collectionEnrichment.version;
    const enrichedCollectionId = collectionEnrichment.collectionId;

    if (
      status === "completed" &&
      typeof version === "number" &&
      version === CURRENT_COLLECTION_ENRICHMENT_VERSION &&
      enrichedCollectionId === collectionId
    ) {
      logger.info(
        "Receipt collection enrichment already up-to-date; skipping",
        {
          userId,
          receiptId,
          collectionId,
        }
      );
      return;
    }

    const collectionRef = firestore
      .collection("users")
      .doc(userId)
      .collection("trips")
      .doc(collectionId);
    const collectionSnap = await collectionRef.get();

    if (!collectionSnap.exists) {
      logger.warn("Collection not found for receipt collection enrichment", {
        userId,
        receiptId,
        collectionId,
      });
      return;
    }

    const collectionData =
      collectionSnap.data() as admin.firestore.DocumentData | undefined;
    const collectionName =
      typeof collectionData?.["name"] === "string" ?
        collectionData["name"] :
        "";
    const collectionType =
      typeof collectionData?.["type"] === "string" ?
        collectionData["type"] :
        "";
    const merchant =
      typeof receiptData["merchant"] === "string" ?
        receiptData["merchant"] :
        typeof receiptData["storeName"] === "string" ?
          receiptData["storeName"] :
          "";
    const items = parseReceiptItems(receiptData);

    await setCollectionEnrichmentStatus(receiptRef, "processing");

    try {
      const allowedCategories = await fetchCollectionCategories(firestore);

      const gptInput = {
        collection_name: collectionName,
        collection_type: collectionType,
        merchant,
        allowed_categories: allowedCategories,
        items: items.map((item) => ({
          name: getItemNameForEnrichment(item),
          price: getItemPriceForEnrichment(item),
        })),
      };

      const suggestions = await parseOpenAIConfigFromResponse(gptInput);
      const validatedSuggestions = validateAndMapSuggestions(
        suggestions,
        items.length,
        allowedCategories
      );

      const suggestionByIndex = new Map<number, ReceiptCollectionSuggestion>();
      for (const suggestion of validatedSuggestions) {
        suggestionByIndex.set(suggestion.index as number, suggestion);
      }

      const enrichedItems = items.map((item, index) => {
        const suggestion = suggestionByIndex.get(index);
        const currentItem = {...item};

        if (suggestion) {
          currentItem["collection_category"] = suggestion.category as string;
        }

        currentItem["collection_enrichment_version"] =
          CURRENT_COLLECTION_ENRICHMENT_VERSION;
        return currentItem;
      });

      await receiptRef.update({
        "items": enrichedItems,
        "collectionEnrichment.status": "completed",
        "collectionEnrichment.version": CURRENT_COLLECTION_ENRICHMENT_VERSION,
        "collectionEnrichment.enrichedAt":
          admin.firestore.FieldValue.serverTimestamp(),
        "collectionEnrichment.collectionId": collectionId,
      });

      void logEvent({
        userId,
        eventName: "collection_enrichment_completed",
        params: {
          itemCount: enrichedItems.length,
          version: CURRENT_COLLECTION_ENRICHMENT_VERSION,
        },
      });
    } catch (error) {
      const safeErrorMessage =
        error instanceof Error ? error.message : String(error);
      logger.error("Receipt collection enrichment failed", {
        userId,
        receiptId,
        collectionId,
        errorMessage: safeErrorMessage,
        errorStack: error instanceof Error ? error.stack : null,
      });
      void logEvent({
        userId,
        eventName: "collection_enrichment_failed",
        params: safeErrorMessage ?
          {error: safeErrorMessage.slice(0, 200)} :
          {},
      });
      await setCollectionEnrichmentStatus(receiptRef, "failed");
    }
  });
