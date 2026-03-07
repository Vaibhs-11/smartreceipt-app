import {onTaskDispatched} from "firebase-functions/v2/tasks";
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";

const CURRENT_ENRICHMENT_VERSION = 1;
const OPENAI_TIMEOUT_MS = 15000;
const MAX_SEARCH_TOKENS = 10;

const FALLBACK_CATEGORIES = [
  "Groceries",
  "Dining & Takeaway",
  "Transport",
  "Travel & Accommodation",
  "Clothing & Accessories",
  "Electronics & Gadgets",
  "Home & Household",
  "Health & Medical",
  "Personal Care & Beauty",
  "Subscriptions",
  "Utilities",
  "Insurance",
  "Education",
  "Professional Services",
  "Entertainment",
  "Gifts & Donations",
  "Other",
];

interface ReceiptEnrichmentTaskPayload {
  userId?: unknown;
  receiptId?: unknown;
}

interface FirestoreManualOverrides {
  category?: unknown;
  brand?: unknown;
  canonical_name?: unknown;
}

interface ReceiptItemSuggestion {
  index: unknown;
  category: unknown;
  brand: unknown;
  canonical_name: unknown;
  search_tokens: unknown;
}

interface EnrichmentResponse {
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

const sanitizeSearchTokens = (value: unknown): string[] => {
  if (!Array.isArray(value)) return [];

  const seen = new Set<string>();
  const result: string[] = [];

  for (const item of value) {
    if (typeof item !== "string") continue;

    const token = item.toLowerCase().trim();
    if (!token || token.length < 2 || token.length > 30) continue;
    if (seen.has(token)) continue;

    seen.add(token);
    result.push(token);

    if (result.length >= MAX_SEARCH_TOKENS) break;
  }

  return result;
};

const parseEnrichmentResponse = (raw: string): {items: ReceiptItemSuggestion[]} => {
  const trimmed = raw.trim();
  const fencedJsonMatch = trimmed.match(/```json\s*([\s\S]*?)\s*```/i);
  const jsonText = fencedJsonMatch ? fencedJsonMatch[1] : trimmed;

  const parsed = JSON.parse(jsonText) as EnrichmentResponse;
  if (!Array.isArray(parsed.items)) {
    throw new Error("OpenAI response missing items array.");
  }

  return {items: parsed.items as ReceiptItemSuggestion[]};
};

const validateAndMapSuggestions = (
  suggestions: ReceiptItemSuggestion[],
  itemCount: number,
  allowedCategories: string[]
): ReceiptItemSuggestion[] => {
  const normalizedAllowed = new Set(allowedCategories);
  const validSuggestions = new Map<number, ReceiptItemSuggestion>();

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

    if (
      suggestion.brand !== null &&
      suggestion.brand !== undefined &&
      typeof suggestion.brand !== "string"
    ) {
      throw new Error(`Invalid brand for index ${index}.`);
    }

    if (
      suggestion.canonical_name !== null &&
      suggestion.canonical_name !== undefined &&
      typeof suggestion.canonical_name !== "string"
    ) {
      throw new Error(`Invalid canonical_name for index ${index}.`);
    }

    if (!Array.isArray(suggestion.search_tokens)) {
      throw new Error(`Missing or invalid search_tokens for index ${index}.`);
    }

    validSuggestions.set(index, suggestion);
  }

  return Array.from(validSuggestions.values());
};

const isManualOverrideEnabled = (
  item: Record<string, unknown>,
  field: keyof FirestoreManualOverrides
): boolean => {
  const rawOverrides = item["manual_overrides"];
  if (!rawOverrides || typeof rawOverrides !== "object") {
    return false;
  }

  const overrides = rawOverrides as FirestoreManualOverrides;
  return overrides[field] === true;
};

const fetchAllowedCategories = async (
  firestore: admin.firestore.Firestore
): Promise<string[]> => {
  try {
    const doc = await firestore.collection("config").doc("categories").get();
    if (!doc.exists) {
      return FALLBACK_CATEGORIES;
    }

    const data = doc.data() ?? {};
    const categories = parseStringArray(data["categories"]);
    return categories.length > 0 ? categories : FALLBACK_CATEGORIES;
  } catch (error) {
    logger.error("Failed to load category config; using fallback categories.", {
      error,
    });
    return FALLBACK_CATEGORIES;
  }
};

const parseOpenAIConfigFromResponse = async (payload: {
  merchant: string;
  allowed_categories: string[];
  items: Array<{name: string; price: number}>;
}): Promise<ReceiptItemSuggestion[]> => {
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) {
    throw new Error("OPENAI_API_KEY environment variable is missing.");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), OPENAI_TIMEOUT_MS);

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      signal: controller.signal,
      body: JSON.stringify({
        model: "gpt-5-mini",
        response_format: {type: "json_object"},
        messages: [
          {
            role: "system",
            content:
              'You are a receipt enrichment assistant. Return only valid JSON with the exact shape {"items":[{"index":number,"category":string,"brand":string|null,"canonical_name":string|null,"search_tokens":[string]}]}. ' +
              "Do not include markdown or explanatory text. " +
              "Use only categories provided in allowed_categories. " +
              "Use null for brand or canonical_name when unknown.",
          },
          {
            role: "user",
            content: JSON.stringify(payload),
          },
        ],
      }),
    });

    if (!response.ok) {
      const errorText = await response.text();
      throw new Error(`OpenAI API failed: ${response.status} ${errorText}`);
    }

    const responseData = (await response.json()) as GPTCompletion;
    const content = responseData.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("OpenAI returned empty response content.");
    }

    const parsed = parseEnrichmentResponse(content);
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
    typeof item === "object" && item !== null
      ? (item as Record<string, unknown>)
      : {}
  );
};

const setEnrichmentStatus = async (
  receiptRef: admin.firestore.DocumentReference,
  status: string
) => {
  await receiptRef.update({"enrichment.status": status});
};

const getItemNameForEnrichment = (item: Record<string, unknown>): string => {
  if (typeof item["original_name"] === "string" && item["original_name"].trim()) {
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

export const processReceiptEnrichment = onTaskDispatched(async (request) => {
  const data = request.data as ReceiptEnrichmentTaskPayload;
  const userId = typeof data.userId === "string" ? data.userId : "";
  const receiptId = typeof data.receiptId === "string" ? data.receiptId : "";

  if (!userId || !receiptId) {
    logger.error("Invalid receipt enrichment task payload", {
      payload: request.data,
    });
    return;
  }

  logger.info("Processing receipt enrichment task", {
    userId,
    receiptId,
    queueName: request.queueName,
    taskId: request.id,
  });

  const firestore = admin.firestore();
  const receiptRef = firestore
    .collection("users")
    .doc(userId)
    .collection("receipts")
    .doc(receiptId);

  const receiptSnap = await receiptRef.get();
  if (!receiptSnap.exists) {
    logger.warn("Receipt not found for enrichment", {userId, receiptId});
    return;
  }

  const receiptData = receiptSnap.data() as admin.firestore.DocumentData;
  const enrichment =
    ((receiptData["enrichment"] as
      | {
          status?: unknown;
          version?: unknown;
        }
      | undefined) ?? {});

  const status = enrichment.status;
  const version = enrichment.version;

  if (
    status === "completed" &&
    typeof version === "number" &&
    version === CURRENT_ENRICHMENT_VERSION
  ) {
    logger.info("Receipt enrichment already up-to-date; skipping", {
      userId,
      receiptId,
    });
    return;
  }

  const merchant =
    typeof receiptData["merchant"] === "string"
      ? receiptData["merchant"]
      : typeof receiptData["storeName"] === "string"
      ? receiptData["storeName"]
      : "";

  const items = parseReceiptItems(receiptData);

  await setEnrichmentStatus(receiptRef, "processing");

  try {
    const allowedCategories = await fetchAllowedCategories(firestore);

    const gptInput = {
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

    const suggestionByIndex = new Map<number, ReceiptItemSuggestion>();
    for (const suggestion of validatedSuggestions) {
      suggestionByIndex.set(suggestion.index as number, suggestion);
    }

    const enrichedItems = items.map((item, index) => {
      const suggestion = suggestionByIndex.get(index);
      const currentItem = {...item};

      if (suggestion) {
        if (!isManualOverrideEnabled(currentItem, "category")) {
          currentItem["category"] = suggestion.category as string;
        }

        if (
          !isManualOverrideEnabled(currentItem, "brand") &&
          (suggestion.brand === null ||
            suggestion.brand === undefined ||
            typeof suggestion.brand === "string")
        ) {
          currentItem["brand"] = suggestion.brand ?? null;
        }

        if (
          !isManualOverrideEnabled(currentItem, "canonical_name") &&
          (suggestion.canonical_name === null ||
            suggestion.canonical_name === undefined ||
            typeof suggestion.canonical_name === "string")
        ) {
          currentItem["canonical_name"] = suggestion.canonical_name ?? null;
        }

        currentItem["search_tokens"] = sanitizeSearchTokens(
          suggestion.search_tokens
        );
      }

      currentItem["enrichment_version"] = CURRENT_ENRICHMENT_VERSION;
      return currentItem;
    });

    await receiptRef.update({
      items: enrichedItems,
      "enrichment.status": "completed",
      "enrichment.version": CURRENT_ENRICHMENT_VERSION,
      "enrichment.enrichedAt": admin.firestore.FieldValue.serverTimestamp(),
    });
  } catch (error) {
    logger.error("Receipt enrichment failed", {userId, receiptId, error});
    await setEnrichmentStatus(receiptRef, "failed");
  }
});