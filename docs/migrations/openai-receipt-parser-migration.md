# OpenAI Receipt Parser Model Migration

Status: assessed, not implemented  
Assessment date: 25 October 2026  
Target release: a release after the share-receipt demo work

## Purpose

ReceiptNest currently sends raw OCR text to an OpenAI model and expects structured JSON describing the receipt. The active parser uses `gpt-4o-mini`, which OpenAI has scheduled for shutdown on 14 January 2027.

This document preserves the completed repository assessment, recommended migration, validation requirements, and a prompt that can be used to start implementation without repeating repository discovery.

The data flow is OCR text to JSON, not XML parsing.

## Decision

Use `gpt-6-luna` for the receipt parser, initially with `reasoning_effort: "none"`.

Reasons:

- OpenAI lists `gpt-6-luna` as the direct replacement for `gpt-4o-mini`.
- It is intended for focused, high-volume, cost-sensitive workloads such as structured extraction.
- It supports Chat Completions and Structured Outputs, allowing a low-risk endpoint migration.
- At the time of assessment, standard token prices were $0.10 per million input tokens and $0.50 per million output tokens, compared with $0.15 and $0.60 for `gpt-4o-mini`.
- Starting with reasoning disabled most closely preserves the current non-reasoning behaviour and avoids unnecessary reasoning-token cost and latency. Test `low` only if representative evaluations demonstrate a material quality improvement.

Official references verified during the assessment:

- Deprecations: https://developers.openai.com/api/docs/deprecations
- GPT-6 Luna: https://developers.openai.com/api/docs/models/gpt-6-luna
- GPT-4o mini: https://developers.openai.com/api/docs/models/gpt-4o-mini
- GPT-6 migration guidance: https://developers.openai.com/api/docs/guides/latest-model
- Structured Outputs: https://developers.openai.com/api/docs/guides/structured-outputs

Model availability, shutdown dates, parameters, and prices are time-sensitive. At implementation time, verify only those facts against the official OpenAI documentation; do not repeat the ReceiptNest architecture assessment unless the relevant code has materially changed.

## Repository Findings

### Active production usage

`functions/src/ocr/parseReceiptWithOpenAI.ts`

- `parseOpenAIReceipt` calls `https://api.openai.com/v1/chat/completions`.
- The request currently uses:
  - `model: "gpt-4o-mini"`
  - `response_format: {type: "json_object"}`
  - `temperature: 0`
  - `max_tokens: 2000`
- The function parses the returned message content with `JSON.parse`.
- Existing sanitisation, receipt classification, selected-total handling, item limits, timeout behaviour, local total extraction, and other fallbacks must be preserved.
- The callable requires authentication, limits calls per user, limits OCR input size, and obtains the API key from the `OPENAI_API_KEY` Firebase secret.

This is the production model call that must be migrated.

### Active Flutter call path

`lib/data/services/ocr/chatgpt_ocr_service.dart`

- `parseRawText` calls the Firebase callable `parseReceiptWithOpenAI`.
- The provider is wired in `lib/presentation/providers/providers.dart` as the parsing stage after Google Vision OCR.
- A model migration in the backend can therefore be deployed independently of an App Store or Play Store release.

### Dormant client-side duplicate

`lib/data/services/ocr/chatgpt_ocr_service.dart` also contains `_parseRawTextWithOpenAI`, a disabled direct call to OpenAI with another hard-coded `gpt-4o-mini` reference.

- `_clientOpenAiParsingEnabled` is `false`.
- The active provider constructs `ChatGptOcrService()` without an OpenAI API key.
- This code should be removed rather than migrated. A distributed mobile client should not contain or accept a production OpenAI secret.
- Preserve the active Firebase callable path.

### Separate model retirement risk

The following enrichment functions use `gpt-5-mini`:

- `functions/src/enrichment/processReceiptEnrichment.ts`
- `functions/src/enrichment/processReceiptCollectionEnrichment.ts`

At the assessment date, OpenAI scheduled `gpt-5-mini` for shutdown on 11 December 2026 and recommended `gpt-5.6-terra` as its direct replacement. These are categorisation/enrichment workloads and require their own evaluation. Do not silently include them in the receipt-parser migration unless the user explicitly broadens the scope.

## Planned Code Changes

### 1. Isolate the OpenAI request contract

In `functions/src/ocr/parseReceiptWithOpenAI.ts`, or a narrowly scoped adjacent module:

- Define the receipt parser model and reasoning effort in one place rather than embedding them in the request.
- Make the request-building logic directly testable without making a network request.
- Do not introduce a new SDK solely for this migration; the existing `fetch` implementation is sufficient.

### 2. Update compatible request parameters

Keep `/v1/chat/completions` for the first migration to avoid changing the model, endpoint, and response parsing at the same time.

The target request should use:

```json
{
  "model": "gpt-6-luna",
  "reasoning_effort": "none",
  "max_completion_tokens": 2000
}
```

Also:

- Remove `temperature`.
- Replace deprecated `max_tokens` with `max_completion_tokens`.
- Retain the current timeouts and backend authentication/rate limits.
- Do not migrate to the Responses API in this release. That can be evaluated separately after the model migration is stable.

### 3. Replace JSON mode with a strict receipt schema

Replace `response_format: {type: "json_object"}` with Chat Completions Structured Outputs using `type: "json_schema"`, `strict: true`, and a schema matching the current `ParsedReceipt` contract.

The schema must cover the fields currently consumed by the backend, including:

- receipt classification
- store name and date
- currency
- candidate totals and selected total index
- final total
- receipt items and prices
- normalized brand
- category
- search keywords

Structured Outputs requirements:

- Every property must be listed as required.
- Conceptually optional values must use nullable types.
- Every object must set `additionalProperties: false`.

Do not remove the current server-side sanitisation and fallbacks. Schema compliance is an additional reliability layer, not a replacement for defensive validation.

### 4. Handle GPT-6 response states and usage

Extend the local response types and handling to cover:

- empty content
- refusal responses
- incomplete or non-successful finish reasons
- input, output, and reasoning-token usage when returned

Operational logs may include model, duration, status, token counts, parsed item count, and whether a fallback ran. They must not include raw OCR text or receipt contents.

### 5. Remove disabled mobile OpenAI code

From `lib/data/services/ocr/chatgpt_ocr_service.dart`:

- Remove `openAiApiKey`.
- Remove `_clientOpenAiParsingEnabled`.
- Remove `_parseRawTextWithOpenAI` and its duplicated prompt/parser.
- Remove imports used only by the disabled direct OpenAI path.
- Keep the active Firebase callable implementation and its public behaviour unchanged.

## Test and Evaluation Requirements

### Automated tests

Add focused tests for:

- request model, reasoning effort, token-limit parameter, and strict schema
- absence of deprecated or incompatible request parameters
- valid responses containing null optional values
- refusals, empty content, malformed responses, and non-success finish reasons
- existing total-selection and local-total fallbacks
- receipt and item limits
- preservation of the backend-to-Flutter response contract

Run at minimum:

```text
cd functions && npm run build
flutter analyze
flutter test
```

Run narrower tests first where available. Do not deploy without explicit approval.

### Representative evaluation

Use an anonymised fixture set of approximately 30–50 OCR results covering:

- clear supermarket receipts
- faded or incomplete OCR
- discounts and negative line items
- multiple possible totals
- tax-inclusive receipts
- different currencies and date formats
- long receipts
- non-receipt documents

Compare the current and candidate implementations on:

- exact total accuracy
- merchant and date accuracy
- line-item extraction accuracy
- false receipt classification
- schema/refusal/fallback rates
- latency
- tokens and cost per successful receipt

Begin with `reasoning_effort: "none"`. Evaluate `low` only if `none` fails an agreed quality threshold, and adopt it only if the quality gain justifies the extra latency and cost.

## Rollout Plan

1. Confirm current OpenAI model status and parameters from the official documentation.
2. Implement the narrow backend request/schema change and dormant-client cleanup.
3. Run automated tests and the representative receipt evaluation.
4. Review the comparison results before changing production.
5. With explicit approval, deploy only the affected Firebase function first.
6. Monitor error rate, refusal/fallback rate, latency, and token cost.
7. Ship the client dead-code cleanup in the associated app release.
8. Handle the two `gpt-5-mini` enrichment functions in a separately scoped migration unless explicitly combined.

No Firestore schema, Firestore rules, subscription behaviour, receipt persistence, UI, iOS project configuration, or Firebase project settings should change as part of this work.

## Ready-to-Use Implementation Prompt

Copy the following prompt into a new ReceiptNest task when ready:

> Implement the OpenAI receipt-parser migration documented in `docs/migrations/openai-receipt-parser-migration.md` in `/Users/vaibhav/smartreceipt-app/smartreceipt-app`.
>
> Treat the saved assessment as the completed architecture investigation: do not repeat broad discovery. First read the repository `AGENTS.md`, the ReceiptNest maintainer skill, the saved migration document, `functions/src/ocr/parseReceiptWithOpenAI.ts`, and the active/dormant paths in `lib/data/services/ocr/chatgpt_ocr_service.dart`. Inspect `git status` and preserve all existing user-owned work.
>
> Before editing, verify only the time-sensitive facts—current support, deprecation status, pricing, and request-parameter compatibility for `gpt-6-luna`—using official OpenAI documentation. If those facts have not materially changed, implement the saved recommendation: keep Chat Completions for this release; migrate the production receipt parser from `gpt-4o-mini` to `gpt-6-luna`; start with `reasoning_effort: "none"`; replace `max_tokens` with `max_completion_tokens`; remove `temperature`; replace JSON mode with strict Structured Outputs matching the existing `ParsedReceipt` contract; preserve all sanitisation, limits, timeouts, fallbacks, and the backend-to-Flutter response contract; add safe usage/error handling and focused tests; and remove the disabled direct-to-OpenAI mobile implementation without changing the active Firebase callable path.
>
> Keep this migration separate from the share-receipt demo and from unrelated refactors. Do not change or deploy the two `gpt-5-mini` enrichment functions unless I explicitly broaden the scope. Do not modify Firestore rules, Firebase project settings, subscription logic, receipt persistence behaviour, or protected iOS/Firebase files. Do not deploy anything without my explicit approval.
>
> Run the relevant TypeScript build, targeted tests, Flutter analysis, and Flutter tests. Create or use anonymised representative receipt fixtures to compare extraction correctness, failures, latency, and token cost. Report the exact files changed, validation results, evaluation outcome, remaining risks, and the deployment command/plan, but stop before deployment.
