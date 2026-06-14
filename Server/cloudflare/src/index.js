/**
 * PvPLedger public match export ingest API.
 * Contract matches Sync/pvpledger_sync/ingest_server.py (local dev server).
 */

const MAX_BODY_BYTES = 5 * 1024 * 1024;

/**
 * @param {unknown} value
 * @returns {string}
 */
function normalizeBatchId(value) {
  return String(value ?? "").trim();
}

/**
 * @param {Date} date
 * @returns {string}
 */
function utcDayPrefix(date) {
  return date.toISOString().slice(0, 10);
}

/**
 * @param {Record<string, unknown>} payload
 * @param {string} batchId
 * @returns {string}
 */
function buildObjectKey(payload, batchId) {
  const uploadedAt = String(payload.uploadedAt ?? "");
  const day = uploadedAt.length >= 10 ? uploadedAt.slice(0, 10) : utcDayPrefix(new Date());
  return `ingested/${day}/batch-${batchId}.json`;
}

/**
 * @param {Request} request
 * @param {string | undefined} expectedToken
 * @returns {Response | null}
 */
function authorizeRequest(request, expectedToken) {
  if (!expectedToken) {
    return null;
  }

  const header = request.headers.get("Authorization") ?? "";
  const expected = `Bearer ${expectedToken}`;
  if (header !== expected) {
    return jsonResponse({ error: "Unauthorized." }, 401);
  }

  return null;
}

/**
 * @param {unknown} body
 * @returns {Response | null}
 */
function validateExportPayload(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return jsonResponse({ error: "Payload must be a JSON object." }, 400);
  }

  const batchId = normalizeBatchId(/** @type {Record<string, unknown>} */ (body).batchId);
  if (!batchId) {
    return jsonResponse({ error: "Missing batchId." }, 400);
  }

  if (!/^[a-zA-Z0-9._-]+$/.test(batchId)) {
    return jsonResponse({ error: "Invalid batchId." }, 400);
  }

  return null;
}

/**
 * @param {unknown} value
 * @param {number} status
 * @returns {Response}
 */
function jsonResponse(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

export default {
  /**
   * @param {Request} request
   * @param {Env} env
   * @returns {Promise<Response>}
   */
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (path === "/api/v1/health" && request.method === "GET") {
      return jsonResponse({
        status: "ok",
        service: "pvpledger-ingest",
        storage: env.EXPORTS_BUCKET ? "r2" : "missing",
      });
    }

    if (path === "/api/v1/exports" && request.method === "POST") {
      const authFailure = authorizeRequest(request, env.INGEST_TOKEN);
      if (authFailure) {
        return authFailure;
      }

      const contentLength = Number(request.headers.get("Content-Length") ?? "0");
      if (!Number.isFinite(contentLength) || contentLength <= 0) {
        return jsonResponse({ error: "Missing request body." }, 400);
      }

      if (contentLength > MAX_BODY_BYTES) {
        return jsonResponse({ error: "Request body too large." }, 413);
      }

      let payload;
      try {
        payload = await request.json();
      } catch {
        return jsonResponse({ error: "Invalid JSON payload." }, 400);
      }

      const validationFailure = validateExportPayload(payload);
      if (validationFailure) {
        return validationFailure;
      }

      const batchId = normalizeBatchId(payload.batchId);
      const objectKey = buildObjectKey(payload, batchId);
      const body = `${JSON.stringify(payload, null, 2)}\n`;

      await env.EXPORTS_BUCKET.put(objectKey, body, {
        httpMetadata: {
          contentType: "application/json; charset=utf-8",
        },
        customMetadata: {
          batchId,
          matchCount: String(payload.matchCount ?? 0),
          region: String(payload.region ?? ""),
          uploadedAt: String(payload.uploadedAt ?? new Date().toISOString()),
          source: String(payload.source ?? "pvpledger-sync"),
        },
      });

      return jsonResponse({
        status: "accepted",
        batchId,
        path: objectKey,
        matchCount: payload.matchCount ?? 0,
      });
    }

    return jsonResponse({ error: "Not found." }, 404);
  },
};
