# QuotaBar

QuotaBar is a macOS 26 SwiftUI menu bar app for tracking DeepSeek API balance and usage.

## What Works

- Native `MenuBarExtra` dashboard with DeepSeek balance, today spend, daily budget progress, model breakdown, and monthly cost chart.
- Local OpenAI-compatible proxy at `http://127.0.0.1:<port>/v1`.
- DeepSeek API key stored in macOS Keychain.
- Caller-facing bearer token so clients do not need the real DeepSeek key.
- Persistent settings for proxy port/token, auto-start, refresh interval, budgets, and alert thresholds.
- Automatic startup restore: QuotaBar can restart the local proxy and refresh balance when the app opens.
- `/v1/chat/completions` forwarding to DeepSeek.
- Non-streaming usage metadata capture into a SwiftData-friendly local ledger.
- SSE response pass-through preserving the upstream response body and headers.
- DeepSeek `/user/balance` fetching and parsing.
- Ledger filtering and CSV/JSON export for metadata-only usage records.
- Provider capability and alert policy abstractions for future AI providers.

QuotaBar stores usage metadata only: timestamp, provider, model, token counts, cost estimate, status code, latency, client label, and anomaly flag. It does not store prompts or responses.

## Run

```bash
swift test
swift build
swift run QuotaBar
```

When running directly from SwiftPM, system notifications are disabled because the process is not inside a `.app` bundle. The rest of the menu bar app and proxy can still be used for development.

## Package Local App

Create a local app bundle:

```bash
Scripts/package-local-app.sh
open dist/QuotaBar.app
```

The script builds a local unsigned `dist/QuotaBar.app` with `LSUIElement` enabled so it behaves like a menu bar app. It is intended for personal use on this Mac, not public distribution.

## Configure A Client

In QuotaBar Settings:

1. Save your DeepSeek API key.
2. Keep or change the local proxy bearer token.
3. Leave "Start proxy when QuotaBar opens" enabled for daily use, or start/restart the proxy manually.

Point OpenAI-compatible clients at the local proxy:

```bash
export OPENAI_BASE_URL="http://127.0.0.1:3847/v1"
export OPENAI_API_KEY="<QuotaBar local bearer token>"
```

The app injects the real DeepSeek key from Keychain when forwarding upstream.

## Current V1 Boundary

- DeepSeek only.
- Supported proxy route: `POST /v1/chat/completions`.
- Pricing uses current DeepSeek USD token pricing for `deepseek-v4-flash` and `deepseek-v4-pro`; `deepseek-chat` and `deepseek-reasoner` map to `deepseek-v4-flash`.
- Local app bundle is unsigned and not notarized.
- Future provider types such as Anthropic, Codex, or window quota plans should implement the core provider capability model rather than changing dashboard code directly.
