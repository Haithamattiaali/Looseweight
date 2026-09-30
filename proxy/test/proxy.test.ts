import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import worker, { type Env, resetRateLimits } from "../src/index";

const env: Env = {
  ANTHROPIC_API_KEY: "server-secret",
  APP_TOKENS: "token-one, token-two",
  RATE_LIMIT_PER_10MIN: "3",
};

const body = {
  model: "claude-opus-test-1",
  max_tokens: 16000,
  messages: [{ role: "user", content: "hi" }],
  tools: [{ name: "search_foods", input_schema: { type: "object" }, strict: true }],
};

function request(path: string, init: RequestInit & { token?: string | null } = {}): Request {
  const headers = new Headers(init.headers);
  if (init.token !== null) headers.set("authorization", `Bearer ${init.token ?? "token-one"}`);
  headers.set("x-device-id", headers.get("x-device-id") ?? "device-abcdef12");
  return new Request(`https://proxy.example.com${path}`, { ...init, headers });
}

function post(payload: unknown, init: RequestInit & { token?: string | null } = {}): Request {
  return request("/v1/messages", { method: "POST", body: typeof payload === "string" ? payload : JSON.stringify(payload), ...init });
}

let upstream: ReturnType<typeof vi.fn>;

beforeEach(() => {
  resetRateLimits();
  upstream = vi.fn(async () => new Response(JSON.stringify({ id: "msg_1" }), { status: 200, headers: { "content-type": "application/json", "request-id": "req_9" } }));
  vi.stubGlobal("fetch", upstream);
  vi.spyOn(console, "log").mockImplementation(() => {});
});

afterEach(() => {
  vi.unstubAllGlobals();
  vi.restoreAllMocks();
});

function upstreamCall(index = 0): { url: string; init: RequestInit; headers: Headers } {
  const call = upstream.mock.calls[index] as [string, RequestInit];
  return { url: call[0], init: call[1], headers: new Headers(call[1].headers) };
}

async function errorOf(response: Response): Promise<{ type: string; message: string }> {
  const parsed = (await response.json()) as { type: string; error: { type: string; message: string } };
  expect(parsed.type).toBe("error");
  return parsed.error;
}

describe("health and routing", () => {
  it("answers health without auth", async () => {
    const response = await worker.fetch(request("/health", { token: null }), env);
    expect(response.status).toBe(200);
    expect(await response.json()).toEqual({ ok: true });
  });

  it("returns 404 for unknown paths and 405 for wrong methods", async () => {
    expect((await worker.fetch(request("/v1/complete", { method: "POST" }), env)).status).toBe(404);
    expect((await worker.fetch(request("/v1/messages", { method: "GET" }), env)).status).toBe(405);
  });
});

describe("authentication", () => {
  it("rejects a missing token", async () => {
    const response = await worker.fetch(post(body, { token: null }), env);
    expect(response.status).toBe(401);
    expect((await errorOf(response)).type).toBe("authentication_error");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects a wrong token", async () => {
    expect((await worker.fetch(post(body, { token: "token-one-extra" }), env)).status).toBe(401);
  });

  it("accepts any listed token", async () => {
    expect((await worker.fetch(post(body, { token: "token-two" }), env)).status).toBe(200);
  });
});

describe("messages pass-through", () => {
  it("injects the server key and never forwards the app token", async () => {
    const response = await worker.fetch(post(body), env);
    expect(response.status).toBe(200);
    expect(response.headers.get("request-id")).toBe("req_9");
    const { url, init, headers } = upstreamCall();
    expect(url).toBe("https://api.anthropic.com/v1/messages");
    expect(init.method).toBe("POST");
    expect(headers.get("x-api-key")).toBe("server-secret");
    expect(headers.get("anthropic-version")).toBe("2023-06-01");
    expect(headers.get("authorization")).toBeNull();
    expect(headers.get("x-device-id")).toBeNull();
    expect(JSON.parse(init.body as string)).toEqual(body);
  });

  it("keeps only allowed beta headers", async () => {
    await worker.fetch(post(body, { headers: { "anthropic-beta": "server-side-fallback-2026-07-01, secret-beta-2099" } }), env);
    expect(upstreamCall().headers.get("anthropic-beta")).toBe("server-side-fallback-2026-07-01");
    await worker.fetch(post(body, { headers: { "anthropic-beta": "secret-beta-2099" } }), env);
    expect(upstreamCall(1).headers.get("anthropic-beta")).toBeNull();
  });

  it("passes upstream errors through unchanged", async () => {
    upstream.mockResolvedValueOnce(new Response(JSON.stringify({ type: "error", error: { type: "overloaded_error", message: "busy" } }), {
      status: 529,
      headers: { "content-type": "application/json", "retry-after": "7" },
    }));
    const response = await worker.fetch(post(body), env);
    expect(response.status).toBe(529);
    expect(response.headers.get("retry-after")).toBe("7");
    expect((await errorOf(response)).type).toBe("overloaded_error");
  });

  it("returns 502 when the AI service cannot be reached", async () => {
    upstream.mockRejectedValueOnce(new TypeError("network down"));
    const response = await worker.fetch(post(body), env);
    expect(response.status).toBe(502);
  });

  it("streams the upstream body without buffering it", async () => {
    const stream = new ReadableStream<Uint8Array>({
      start(controller) {
        controller.enqueue(new TextEncoder().encode("event: message_start\n\n"));
        controller.enqueue(new TextEncoder().encode("event: message_stop\n\n"));
        controller.close();
      },
    });
    upstream.mockResolvedValueOnce(new Response(stream, { status: 200, headers: { "content-type": "text/event-stream" } }));
    const response = await worker.fetch(post({ ...body, stream: true }), env);
    expect(response.headers.get("content-type")).toBe("text/event-stream");
    expect(await response.text()).toBe("event: message_start\n\nevent: message_stop\n\n");
  });
});

describe("validation", () => {
  it.each([
    ["a model outside the pattern", { ...body, model: "gpt-9" }],
    ["too many output tokens", { ...body, max_tokens: 64000 }],
    ["a fractional max_tokens", { ...body, max_tokens: 10.5 }],
    ["too many messages", { ...body, messages: Array.from({ length: 41 }, () => ({ role: "user", content: "x" })) }],
    ["a server tool", { ...body, tools: [{ type: "web_search_20260209", name: "web_search" }] }],
    ["a tool without schema", { ...body, tools: [{ name: "x" }] }],
    ["a non-object body", [1, 2, 3]],
  ])("rejects %s", async (_label, payload) => {
    const response = await worker.fetch(post(payload), env);
    expect(response.status).toBe(400);
    expect((await errorOf(response)).type).toBe("invalid_request_error");
    expect(upstream).not.toHaveBeenCalled();
  });

  it("rejects invalid JSON", async () => {
    const response = await worker.fetch(post("{not json"), env);
    expect(response.status).toBe(400);
  });

  it("rejects bodies over the size limit", async () => {
    const small: Env = { ...env, MAX_BODY_BYTES: "100" };
    const response = await worker.fetch(post({ ...body, padding: "x".repeat(500) }), small);
    expect(response.status).toBe(413);
    expect(upstream).not.toHaveBeenCalled();
  });
});

describe("models", () => {
  it("forwards the models list with its query string", async () => {
    upstream.mockResolvedValueOnce(new Response(JSON.stringify({ data: [{ id: "claude-opus-test-1" }] }), { status: 200, headers: { "content-type": "application/json" } }));
    const response = await worker.fetch(request("/v1/models?limit=100"), env);
    expect(response.status).toBe(200);
    expect(upstreamCall().url).toBe("https://api.anthropic.com/v1/models?limit=100");
    expect(upstreamCall().headers.get("x-api-key")).toBe("server-secret");
  });

  it("forwards a single model lookup", async () => {
    await worker.fetch(request("/v1/models/claude-sonnet-test-2"), env);
    expect(upstreamCall().url).toBe("https://api.anthropic.com/v1/models/claude-sonnet-test-2");
  });
});

describe("rate limiting", () => {
  it("limits each device and says when to retry", async () => {
    for (let index = 0; index < 3; index++) {
      expect((await worker.fetch(post(body), env)).status).toBe(200);
    }
    const blocked = await worker.fetch(post(body), env);
    expect(blocked.status).toBe(429);
    expect(Number(blocked.headers.get("retry-after"))).toBeGreaterThan(0);
    const otherDevice = await worker.fetch(post(body, { headers: { "x-device-id": "device-99999999" } }), env);
    expect(otherDevice.status).toBe(200);
  });

  it("uses the Cloudflare rate limiting binding when present", async () => {
    const limiter = { limit: vi.fn(async () => ({ success: false })) };
    const response = await worker.fetch(post(body), { ...env, RATE_LIMITER: limiter });
    expect(response.status).toBe(429);
    expect(limiter.limit).toHaveBeenCalledWith({ key: "device:device-abcdef12" });
  });
});
