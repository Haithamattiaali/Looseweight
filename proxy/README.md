# Looseweight proxy

A small Cloudflare Worker between the app and the Anthropic API, so the API key never ships inside the app.

It checks every request (app token, allowed models, size, max tokens, app-defined tools only), limits each device to 40 requests per 10 minutes, and never logs meal photos.

## Deploy

```bash
cd proxy
npm install
npx wrangler@latest login
npx wrangler@latest secret put ANTHROPIC_API_KEY   # your Anthropic key
npx wrangler@latest secret put APP_TOKENS          # any long random text; comma-separate several
npx wrangler@latest deploy                         # prints the Worker URL
```

## Connect the app

iPhone → **Settings → AI analysis → Looseweight Cloud** → paste the Worker URL and one of the app tokens.

To ship the URL and token inside a build instead, set `LW_PROXY_URL` and `LW_PROXY_TOKEN` in the Xcode build settings.

## Test

```bash
npm test && npm run typecheck
```
