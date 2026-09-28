export interface RateLimiter {
  limit(options: { key: string }): Promise<{ success: boolean }>;
}

export interface Env {
  ANTHROPIC_API_KEY: string;
  /** Comma-separated tokens the app may send as `Authorization: Bearer …`. */
  APP_TOKENS: string;
  ALLOWED_BETAS?: string;
  MODEL_PATTERN?: string;
  MAX_BODY_BYTES?: string;
  MAX_OUTPUT_TOKENS?: string;
  RATE_LIMIT_PER_10MIN?: string;
  RATE_LIMITER?: RateLimiter;
  UPSTREAM_URL?: string;
}

const DEFAULT_BETAS = "server-side-fallback-2026-07-01";
const DEFAULT_MODEL_PATTERN = "^claude-(opus|sonnet|haiku)-[a-z0-9-]+$";
const DEFAULT_MAX_BODY_BYTES = 12_000_000;
const DEFAULT_MAX_OUTPUT_TOKENS = 32_000;
const DEFAULT_RATE_LIMIT = 40;
const RATE_WINDOW_MS = 10 * 60 * 1000;
const MAX_MESSAGES = 40;
const PASSED_HEADERS = ["content-type", "request-id", "retry-after"];

function errorResponse(status: number, type: string, message: string, extraHeaders: Record<string, string> = {}): Response {
  return new Response(JSON.stringify({ type: "error", error: { type, message } }), {
    status,
    headers: { "content-type": "application/json", ...extraHeaders },
  });
}

function list(value: string | undefined, fallback: string): string[] {
  return (value ?? fallback)
    .split(",")
    .map((item) => item.trim())
    .filter((item) => item.length > 0);
}

function constantTimeEqual(a: string, b: string): boolean {
  const left = new TextEncoder().encode(a);
  const right = new TextEncoder().encode(b);
  let difference = left.length ^ right.length;
  const length = Math.max(left.length, right.length);
  for (let index = 0; index < length; index++) {
    difference |= (left[index] ?? 0) ^ (right[index] ?? 0);
  }
  return difference === 0;
}

function isAuthorized(request: Request, env: Env): boolean {
  const match = /^Bearer\s+(\S+)$/i.exec(request.headers.get("authorization") ?? "");
  const token = match?.[1];
  if (!token) return false;
  let authorized = false;
  for (const candidate of list(env.APP_TOKENS, "")) {
    if (constantTimeEqual(token, candidate)) authorized = true;
  }
  return authorized;
}

function clientKey(request: Request): string {
  const device = request.headers.get("x-device-id");
  if (device && /^[A-Za-z0-9-]{8,128}$/.test(device)) return `device:${device}`;
  return `ip:${request.headers.get("cf-connecting-ip") ?? "unknown"}`;
}

const windows = new Map<string, { start: number; count: number }>();

/** Clears the in-memory limiter (tests only). */
export function resetRateLimits(): void {
  windows.clear();
}

async function checkRateLimit(key: string, env: Env, now = Date.now()): Promise<number | null> {
  if (env.RATE_LIMITER) {
    const { success } = await env.RATE_LIMITER.limit({ key });
    return success ? null : 60;
  }
  const limit = Number(env.RATE_LIMIT_PER_10MIN ?? DEFAULT_RATE_LIMIT);
  const entry = windows.get(key);
  if (!entry || now - entry.start >= RATE_WINDOW_MS) {
    windows.set(key, { start: now, count: 1 });
    return null;
  }
  if (entry.count >= limit) return Math.max(1, Math.ceil((entry.start + RATE_WINDOW_MS - now) / 1000));
  entry.count += 1;
  return null;
}

function upstreamHeaders(request: Request, env: Env): Headers {
  const headers = new Headers({
    "x-api-key": env.ANTHROPIC_API_KEY,
    "anthropic-version": "2023-06-01",
    "content-type": "application/json",
  });
  const allowed = new Set(list(env.ALLOWED_BETAS, DEFAULT_BETAS));
  const kept = list(request.headers.get("anthropic-beta") ?? "", "").filter((beta) => allowed.has(beta));
  if (kept.length > 0) headers.set("anthropic-beta", kept.join(","));
  return headers;
}

async function forward(pending: Promise<Response>): Promise<Response> {
  let upstream: Response;
  try {
    upstream = await pending;
  } catch {
    return errorResponse(502, "api_error", "Could not reach the AI service.");
  }
  const headers = new Headers();
  for (const name of PASSED_HEADERS) {
    const value = upstream.headers.get(name);
    if (value) headers.set(name, value);
  }
  return new Response(upstream.body, { status: upstream.status, headers });
}

async function readBody(request: Request, maxBytes: number): Promise<string | Response> {
  const tooLarge = () => errorResponse(413, "request_too_large", `The request is larger than ${maxBytes} bytes.`);
  if (Number(request.headers.get("content-length") ?? "0") > maxBytes) return tooLarge();
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks: Uint8Array[] = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return tooLarge();
    }
    chunks.push(value);
  }
  const merged = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    merged.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return new TextDecoder().decode(merged);
}

/** Returns a problem description, or null when the request may go upstream. */
export function validateMessagesBody(body: unknown, env: Env): string | null {
  if (typeof body !== "object" || body === null || Array.isArray(body)) return "The body must be a JSON object.";
  const fields = body as Record<string, unknown>;
  const pattern = new RegExp(env.MODEL_PATTERN ?? DEFAULT_MODEL_PATTERN);
  if (typeof fields.model !== "string" || !pattern.test(fields.model)) return "This model is not allowed through the proxy.";
  const maxOutput = Number(env.MAX_OUTPUT_TOKENS ?? DEFAULT_MAX_OUTPUT_TOKENS);
  if (typeof fields.max_tokens !== "number" || !Number.isInteger(fields.max_tokens) || fields.max_tokens < 1 || fields.max_tokens > maxOutput) {
    return `max_tokens must be a whole number from 1 to ${maxOutput}.`;
  }
  if (!Array.isArray(fields.messages) || fields.messages.length > MAX_MESSAGES) return `messages must be a list of at most ${MAX_MESSAGES}.`;
  if (fields.tools !== undefined) {
    if (!Array.isArray(fields.tools)) return "tools must be a list.";
    for (const tool of fields.tools) {
      if (typeof tool !== "object" || tool === null) return "Each tool must be an object.";
      const definition = tool as Record<string, unknown>;
      if (definition.type !== undefined && definition.type !== "custom") return "Only app-defined tools are allowed.";
      if (typeof definition.input_schema !== "object" || definition.input_schema === null) return "Each tool needs an input_schema.";
    }
  }
  return null;
}

async function route(request: Request, env: Env, url: URL): Promise<Response> {
  if (url.pathname === "/health") {
    return new Response(JSON.stringify({ ok: true }), { headers: { "content-type": "application/json" } });
  }
  const isMessages = url.pathname === "/v1/messages";
  const isModels = url.pathname === "/v1/models" || /^\/v1\/models\/[A-Za-z0-9._:-]+$/.test(url.pathname);
  if (!isMessages && !isModels) return errorResponse(404, "not_found_error", "Not found.");
  if ((isMessages && request.method !== "POST") || (isModels && request.method !== "GET")) {
    return errorResponse(405, "invalid_request_error", "Method not allowed.");
  }
  if (!isAuthorized(request, env)) return errorResponse(401, "authentication_error", "Missing or invalid app token.");

  const retryAfter = await checkRateLimit(clientKey(request), env);
  if (retryAfter !== null) {
    return errorResponse(429, "rate_limit_error", "Too many requests. Try again shortly.", { "retry-after": String(retryAfter) });
  }

  const upstream = (env.UPSTREAM_URL ?? "https://api.anthropic.com").replace(/\/+$/, "");
  if (isModels) {
    return forward(fetch(`${upstream}${url.pathname}${url.search}`, { method: "GET", headers: upstreamHeaders(request, env) }));
  }

  const text = await readBody(request, Number(env.MAX_BODY_BYTES ?? DEFAULT_MAX_BODY_BYTES));
  if (text instanceof Response) return text;
  let body: unknown;
  try {
    body = JSON.parse(text);
  } catch {
    return errorResponse(400, "invalid_request_error", "The body is not valid JSON.");
  }
  const problem = validateMessagesBody(body, env);
  if (problem) return errorResponse(400, "invalid_request_error", problem);
  return forward(fetch(`${upstream}/v1/messages`, { method: "POST", headers: upstreamHeaders(request, env), body: text }));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const started = Date.now();
    const url = new URL(request.url);
    let response: Response;
    try {
      response = await route(request, env, url);
    } catch {
      response = errorResponse(500, "api_error", "Proxy error.");
    }
    // Metadata only: bodies hold users' meal photos and are never logged.
    console.log(`${request.method} ${url.pathname} ${response.status} ${Date.now() - started}ms`);
    return response;
  },
};
