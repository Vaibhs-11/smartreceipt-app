import {onCall, HttpsError} from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";
import {
  assertPayloadSize,
  assertUserRateLimit,
} from "../security/rateLimit";

const OPENAI_TIMEOUT_MS = 45000;
const MAX_OCR_TEXT_LENGTH = 20000;
const MAX_PARSE_PAYLOAD_BYTES = 128 * 1024;
const PARSE_RECEIPT_MAX_CALLS_PER_HOUR = 20;
const MAX_ITEMS = 200;
const MAX_KEYWORDS = 30;
const MAX_ITEM_NAME_LENGTH = 300;

interface GPTChoice {
  message?: {
    content?: string;
  };
}

interface GPTCompletion {
  choices?: GPTChoice[];
}

interface ParsedReceiptItem {
  name?: unknown;
  price?: unknown;
  priceConfidence?: unknown;
}

interface ParsedTotalCandidate {
  label?: unknown;
  amount?: unknown;
  context?: unknown;
}

interface ParsedReceipt {
  isReceipt?: unknown;
  receiptRejectionReason?: unknown;
  storeName?: unknown;
  date?: unknown;
  items?: unknown;
  totals?: unknown;
  selectedTotalIndex?: unknown;
  total?: unknown;
  currency?: unknown;
  normalizedBrand?: unknown;
  category?: unknown;
  searchKeywords?: unknown;
}

const buildReceiptPrompt = (rawText: string): string => {
  return `You are a strict receipt parser.

Your task is to extract structured data from the receipt text below.
Be precise, conservative, and deterministic.

REQUIRED FIELDS

Extract these exact values:

- isReceipt:
  boolean.
  Set true when the text represents ANY valid proof of a financial transaction,
  including but not limited to retail purchase receipts, tax invoices, service
  receipts, utility or telecom invoices, and subscription or billing statements
  that show a charge.

  A receipt may contain a single line item, multiple items, no explicit item
  list, or service-based charges instead of physical goods.

  Set false ONLY when the content is clearly unrelated to a transaction, such
  as bank statements listing multiple transactions, ads, random text, chat
  screenshots, or emails without billing or payment information.

  If unsure, prefer true over false.

- receiptRejectionReason:
  short explanation ONLY when isReceipt is false.
  Set null when isReceipt is true.

- storeName:
  primary store name.

- date:
  purchase date in YYYY-MM-DD format. If unable to determine a date, return an
  empty string.

- items:
  list of item objects. Each item must include:
    - name: exact item name as shown on the receipt
    - price: exact numeric price OR null when truly unavailable
    - priceConfidence: "high" or "low"

  If no clear item list exists, create one item using the best available
  description, assign the total amount only if no better breakdown exists, and
  set priceConfidence to "low".

  Never assign discounts or negative values as item prices. Do not invent
  prices or derive item prices from totals.

- total:
  exact final billed amount. Choose the amount explicitly labelled TOTAL,
  GRAND TOTAL, INVOICE TOTAL, or the final amount payable. Do not round.

- totals:
  list of candidate totals with label, amount, and context.

- selectedTotalIndex:
  0-based index into totals for the selected final total.

- currency:
  ISO-4217 code where possible. Use explicit evidence from currency symbols,
  tax names, address location, government identifiers, tax ID formats, and
  country-specific tax terms. If no reliable evidence exists, return null.

RECEIPT-LEVEL ENRICHMENT

Also derive these metadata fields for search enrichment:

- normalizedBrand: most likely brand name, corrected for OCR errors. Return
  null if not reasonably confident.
- category: concrete, high-level product type. Return null when not reasonably
  inferable.
- searchKeywords: lowercased, de-duplicated keywords useful for search.

IMPORTANT RULES

- Return JSON only. No markdown. No explanations.
- Do not round monetary amounts.
- Preserve cents exactly as written.
- Never invent prices, brands, or products.
- If the content is not a receipt, set isReceipt false, provide
  receiptRejectionReason, and keep monetary fields at 0 and strings empty where
  unsure.

Example response format:

{
  "isReceipt": true,
  "receiptRejectionReason": null,
  "storeName": "Example Store",
  "date": "2025-08-17",
  "items": [
    {"name": "ITEM A", "price": 12.34, "priceConfidence": "high"},
    {"name": "ITEM B", "price": null, "priceConfidence": "low"}
  ],
  "totals": [
    {"label": "TOTAL", "amount": 17.34, "context": "TOTAL 17.34"}
  ],
  "selectedTotalIndex": 0,
  "total": 17.34,
  "currency": "AUD",
  "normalizedBrand": "Breville",
  "category": "coffee machine",
  "searchKeywords": ["breville", "oracle", "coffee machine"]
}

RECEIPT TEXT

${rawText}`;
};

const cleanModelContent = (content: string): string => {
  let cleaned = content.trim();
  if (cleaned.startsWith("```")) {
    const firstNewline = cleaned.indexOf("\n");
    const lastFence = cleaned.lastIndexOf("```");
    if (firstNewline !== -1 && lastFence !== -1 && lastFence > firstNewline) {
      cleaned = cleaned.substring(firstNewline + 1, lastFence).trim();
    }
  }
  return cleaned;
};

const parseBool = (value: unknown): boolean | null => {
  if (typeof value === "boolean") return value;
  if (typeof value !== "string") return null;
  const normalized = value.trim().toLowerCase();
  if (normalized === "true") return true;
  if (normalized === "false") return false;
  return null;
};

const normalizeOptionalString = (value: unknown): string | null => {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed ? trimmed : null;
};

const numberFromDynamic = (value: unknown): number | null => {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value !== "string") return null;

  const trimmed = value.trim();
  if (!trimmed) return null;

  const direct = Number(trimmed);
  if (Number.isFinite(direct)) return direct;

  const cleaned = trimmed.replace(/[^0-9.-]/g, "");
  if (!cleaned) return null;

  const parsed = Number(cleaned);
  return Number.isFinite(parsed) ? parsed : null;
};

const parseMoneyToken = (value: string): number | null => {
  let normalized = value.replace(/\s/g, "");
  if (normalized.includes(",") && normalized.includes(".")) {
    if (normalized.lastIndexOf(".") > normalized.lastIndexOf(",")) {
      normalized = normalized.replace(/,/g, "");
    } else {
      normalized = normalized.replace(/\./g, "").replace(/,/g, ".");
    }
  } else {
    normalized = normalized.replace(/,/g, ".");
  }
  const parsed = Number(normalized);
  return Number.isFinite(parsed) ? parsed : null;
};

const localExtractTotal = (text: string): number | null => {
  const lines = text.split(/[\r\n]+/);
  const moneyRe = new RegExp(
    "(?:AUD\\s*|\\$)?\\s*" +
      "([0-9]{1,3}(?:[.,\\s][0-9]{3})*(?:[.,][0-9]{2})|" +
      "[0-9]+(?:[.,][0-9]{2}))",
    "g"
  );
  const excludedPhrases = [
    "tendered",
    "change",
    "balance due",
    "cash received",
    "amount tendered",
  ];
  const keywordWeights: Record<string, number> = {
    "total paid": 220,
    "total inc tax": 210,
    "grand total": 200,
    "amount payable": 190,
    "invoice total": 180,
    "amount due": 170,
    "total": 160,
    "subtotal": 120,
    "paid": 110,
    "eftpos": 100,
    "payment": 100,
  };

  const allMoney: number[] = [];
  const candidates: Array<{value: number; score: number}> = [];

  for (const line of lines) {
    moneyRe.lastIndex = 0;
    let match = moneyRe.exec(line);
    while (match) {
      const parsed = parseMoneyToken(match[1]);
      if (parsed !== null) allMoney.push(parsed);
      match = moneyRe.exec(line);
    }
  }

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;
    const lower = line.toLowerCase();
    if ((lower.includes("gst") && lower.includes("total")) ||
      lower.includes("avail bal") ||
      lower.includes("available balance") ||
      excludedPhrases.some((phrase) => lower.includes(phrase))) {
      continue;
    }

    let bestWeight = 0;
    for (const [keyword, weight] of Object.entries(keywordWeights)) {
      if (lower.includes(keyword)) bestWeight = Math.max(bestWeight, weight);
    }
    if (bestWeight === 0) continue;

    const amounts: number[] = [];
    const collectAmounts = (candidateLine: string) => {
      moneyRe.lastIndex = 0;
      let match = moneyRe.exec(candidateLine);
      while (match) {
        const parsed = parseMoneyToken(match[1]);
        if (parsed !== null) amounts.push(parsed);
        match = moneyRe.exec(candidateLine);
      }
    };

    collectAmounts(line);
    for (let j = 1;
      j <= 3 && i + j < lines.length && amounts.length === 0;
      j++) {
      const adjacent = lines[i + j].trim();
      const adjacentLower = adjacent.toLowerCase();
      if (!adjacent ||
        excludedPhrases.some((phrase) => adjacentLower.includes(phrase))) {
        continue;
      }
      collectAmounts(adjacent);
    }

    for (const amount of amounts) {
      candidates.push({
        value: amount,
        score: bestWeight + (amount === 0 ? -100 : 0),
      });
    }
  }

  if (candidates.length === 0) {
    const start = Math.max(0, lines.length - 12);
    for (let i = start; i < lines.length; i++) {
      const line = lines[i].trim();
      const lower = line.toLowerCase();
      if (!line ||
        lower.includes("avail bal") ||
        lower.includes("available balance") ||
        excludedPhrases.some((phrase) => lower.includes(phrase))) {
        continue;
      }
      moneyRe.lastIndex = 0;
      let match = moneyRe.exec(line);
      while (match) {
        const parsed = parseMoneyToken(match[1]);
        if (parsed !== null) {
          candidates.push({
            value: parsed,
            score: 75 + (parsed === 0 ? -100 : 0),
          });
        }
        match = moneyRe.exec(line);
      }
    }
  }

  if (candidates.length > 0) {
    let bestNonZero: number | null = null;
    let bestZero: number | null = null;
    for (const candidate of candidates) {
      if (candidate.value > 0 &&
        (bestNonZero === null || candidate.value > bestNonZero)) {
        bestNonZero = candidate.value;
      } else if (candidate.value === 0) {
        bestZero = 0;
      }
    }
    return bestNonZero ?? bestZero;
  }

  return allMoney.length > 0 ? Math.max(...allMoney) : null;
};

const inferCurrency = (
  rawText: string,
  parsedCurrency: string | null
): string | null => {
  const explicit = rawText.match(
    /\b(AUD|USD|GBP|EUR|CAD|NZD|SGD|INR|JPY|CNY)\b/i
  );
  if (explicit) return explicit[1].toUpperCase();

  const lower = rawText.toLowerCase();
  if (/\b(VIC|NSW|QLD|WA|SA|TAS|ACT|NT)\b/i.test(rawText) ||
    /\babn\b/i.test(rawText) ||
    lower.includes(".au") ||
    /\b(melbourne|sydney|brisbane|perth|adelaide)\b/i.test(rawText)) {
    return "AUD";
  }
  if (/SGST|CGST|GSTIN|HSN|₹|\bindia\b/i.test(rawText)) return "INR";
  if (/GST\/?HST|\bcanada\b|\.ca\b/i.test(rawText)) return "CAD";
  if (/£|\bgbp\b|\buk\b|united kingdom/i.test(rawText)) return "GBP";
  if (/€|\beur\b|\beuro\b/i.test(rawText)) return "EUR";
  if (/¥|\bjpy\b|\byen\b|\bjapan\b/i.test(rawText)) return "JPY";
  if (/\bnzd\b|new zealand|\.nz\b/i.test(rawText)) return "NZD";
  if (/\bsgd\b|\bsingapore\b|\.sg\b/i.test(rawText)) return "SGD";
  if (/\busd\b|united states|\.us\b/i.test(rawText)) return "USD";
  return parsedCurrency ? parsedCurrency.toUpperCase() : null;
};

const sanitizeItems = (items: unknown): Array<{
  name: string;
  price: number | null;
  priceConfidence: string;
}> => {
  if (!Array.isArray(items)) return [];
  const sanitized = [];
  for (const item of items.slice(0, MAX_ITEMS)) {
    if (!item || typeof item !== "object") continue;
    const record = item as ParsedReceiptItem;
    const name = String(record.name ?? "")
      .trim()
      .slice(0, MAX_ITEM_NAME_LENGTH);
    if (!name) continue;
    const rawPrice = record.price;
    let price = numberFromDynamic(rawPrice);
    let priceConfidence =
      String(record.priceConfidence ?? "").toLowerCase() === "low" ?
        "low" :
        "high";
    const hadDigits = typeof rawPrice === "number" ||
      (typeof rawPrice === "string" && /\d/.test(rawPrice));

    if (price !== null && price <= 0) {
      price = null;
      priceConfidence = "low";
    }
    if (!hadDigits && rawPrice !== null && rawPrice !== undefined) {
      price = null;
      priceConfidence = "low";
    }
    sanitized.push({name, price, priceConfidence});
  }
  return sanitized;
};

const sanitizeTotals = (totals: unknown): Array<{
  label: string;
  amount: number | null;
  context: string;
}> => {
  if (!Array.isArray(totals)) return [];
  return totals.slice(0, 20).map((item) => {
    const record = item && typeof item === "object" ?
      item as ParsedTotalCandidate :
      {};
    return {
      label: String(record.label ?? ""),
      amount: numberFromDynamic(record.amount),
      context: String(record.context ?? "").slice(0, 500),
    };
  });
};

const sanitizeKeywords = (keywords: unknown): string[] => {
  if (!Array.isArray(keywords)) return [];
  const seen = new Set<string>();
  const sanitized: string[] = [];
  for (const keyword of keywords) {
    if (keyword === null || keyword === undefined) continue;
    const normalized = String(keyword).trim().toLowerCase();
    if (!normalized || seen.has(normalized)) continue;
    seen.add(normalized);
    sanitized.push(normalized);
    if (sanitized.length >= MAX_KEYWORDS) break;
  }
  return sanitized;
};

const parseSelectedTotal = (
  parsed: ParsedReceipt,
  totals: Array<{amount: number | null}>
): number | null => {
  const rawIndex = parsed.selectedTotalIndex;
  if (typeof rawIndex !== "number" || !Number.isInteger(rawIndex)) {
    return null;
  }
  if (rawIndex < 0 || rawIndex >= totals.length) return null;
  return totals[rawIndex].amount;
};

const parseOpenAIReceipt = async (
  rawText: string,
  apiKey: string
): Promise<ParsedReceipt> => {
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
        model: "gpt-4o-mini",
        response_format: {type: "json_object"},
        messages: [
          {
            role: "system",
            content: "You are a precise JSON-producing receipt parser.",
          },
          {
            role: "user",
            content: buildReceiptPrompt(rawText),
          },
        ],
        temperature: 0,
        max_tokens: 2000,
      }),
    });

    if (!response.ok) {
      throw new Error(`openai_status_${response.status}`);
    }

    const responseData = await response.json() as GPTCompletion;
    const content = responseData.choices?.[0]?.message?.content;
    if (!content) {
      throw new Error("openai_empty_content");
    }

    return JSON.parse(cleanModelContent(content)) as ParsedReceipt;
  } finally {
    clearTimeout(timeout);
  }
};

export const parseReceiptWithOpenAI = onCall(
  {
    secrets: ["OPENAI_API_KEY"],
    timeoutSeconds: 60,
    memory: "512MiB",
  },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    assertPayloadSize(request.data, MAX_PARSE_PAYLOAD_BYTES);

    const rawText = request.data?.rawText;
    if (typeof rawText !== "string") {
      throw new HttpsError("invalid-argument", "rawText must be a string");
    }

    const trimmedRawText = rawText.trim();
    if (!trimmedRawText) {
      throw new HttpsError("invalid-argument", "No OCR text provided");
    }
    if (trimmedRawText.length > MAX_OCR_TEXT_LENGTH) {
      throw new HttpsError("invalid-argument", "OCR text is too long");
    }

    await assertUserRateLimit({
      firestore: admin.firestore(),
      uid,
      functionName: "parseReceiptWithOpenAI",
      maxCalls: PARSE_RECEIPT_MAX_CALLS_PER_HOUR,
    });

    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      logger.error("OpenAI receipt parsing secret missing", {uid});
      throw new HttpsError(
        "failed-precondition",
        "Receipt parsing is not configured"
      );
    }

    try {
      const parsed = await parseOpenAIReceipt(trimmedRawText, apiKey);

      const isReceipt = parseBool(parsed.isReceipt) ?? true;
      const receiptRejectionReason =
        normalizeOptionalString(parsed.receiptRejectionReason);
      const storeName =
        normalizeOptionalString(parsed.storeName) ?? "Unknown Store";
      const date = normalizeOptionalString(parsed.date) ?? "";
      const totals = sanitizeTotals(parsed.totals);
      const gptSelectedTotal = parseSelectedTotal(parsed, totals);
      const gptTotal = numberFromDynamic(parsed.total);
      const gptChosen = gptSelectedTotal ?? gptTotal;
      const localTotal = localExtractTotal(trimmedRawText);
      const total =
        gptChosen === null && localTotal !== null ?
          localTotal :
          gptChosen !== null && localTotal === null ?
            gptChosen :
            gptChosen !== null && localTotal !== null ?
              Math.abs(gptChosen - localTotal) < 0.01 ?
                gptChosen :
                localTotal :
              0;
      const normalizedBrand = normalizeOptionalString(parsed.normalizedBrand);
      const category = normalizeOptionalString(parsed.category);
      const searchKeywords = sanitizeKeywords(parsed.searchKeywords);
      for (const extra of [normalizedBrand, category]) {
        const normalized = extra?.trim().toLowerCase();
        if (
          normalized &&
          searchKeywords.length < MAX_KEYWORDS &&
          !searchKeywords.includes(normalized)
        ) {
          searchKeywords.push(normalized);
        }
      }
      const selectedTotalIndex =
        typeof parsed.selectedTotalIndex === "number" &&
        Number.isInteger(parsed.selectedTotalIndex) &&
        parsed.selectedTotalIndex >= 0 &&
        parsed.selectedTotalIndex < totals.length ?
          parsed.selectedTotalIndex :
          null;

      logger.info("OpenAI receipt parsing completed", {
        uid,
        textLength: trimmedRawText.length,
        itemCount: Array.isArray(parsed.items) ? parsed.items.length : 0,
        isReceipt,
      });

      return {
        isReceipt,
        receiptRejectionReason,
        storeName,
        date,
        total,
        rawText: trimmedRawText,
        items: sanitizeItems(parsed.items),
        totals,
        selectedTotalIndex,
        currency: inferCurrency(
          trimmedRawText,
          normalizeOptionalString(parsed.currency)
        ),
        searchKeywords,
        normalizedBrand,
        category,
      };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      logger.error("OpenAI receipt parsing failed", {
        uid,
        textLength: trimmedRawText.length,
        code: message.startsWith("openai_status_") ? message : "parse_failed",
      });
      throw new HttpsError(
        "internal",
        "Receipt parsing failed. Please try again."
      );
    }
  }
);
