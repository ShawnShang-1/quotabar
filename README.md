# QuotaBar

QuotaBar is a macOS 26 SwiftUI menu bar app for tracking DeepSeek API balance and usage.

## What Works

- Native `MenuBarExtra` dashboard with DeepSeek balance, today spend, daily budget progress, model breakdown, and monthly cost chart.
- Local OpenAI-compatible proxy at `http://127.0.0.1:<port>/v1`.
- Local Anthropic-compatible DeepSeek proxy at `http://127.0.0.1:<port>/anthropic`.
- DeepSeek API key stored in macOS Keychain.
- Caller-facing bearer token so clients do not need the real DeepSeek key.
- Persistent settings for proxy port/token, auto-start, refresh interval, budgets, and alert thresholds.
- Automatic startup restore: QuotaBar can restart the local proxy and refresh balance when the app opens.
- `/v1/chat/completions` and `/anthropic/v1/messages` forwarding to DeepSeek.
- OpenAI-compatible and Anthropic Messages usage metadata capture into a SwiftData-friendly local ledger.
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

For CC Switch / Claude Code using DeepSeek's Anthropic Messages compatibility, keep the API format as Anthropic Messages and point it at QuotaBar:

```json
{
  "env": {
    "ANTHROPIC_BASE_URL": "http://127.0.0.1:3847/anthropic",
    "ANTHROPIC_AUTH_TOKEN": "<QuotaBar local bearer token>",
    "ANTHROPIC_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "deepseek-v4-flash[1m]",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "deepseek-v4-pro[1m]",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "deepseek-v4-pro[1m]"
  }
}
```

Do not put the real DeepSeek key in CC Switch when routing through QuotaBar. Put the real key in QuotaBar, then paste QuotaBar's local bearer token into CC Switch's API Key field.

## Current Boundary

- DeepSeek only.
- Supported proxy routes: `POST /v1/chat/completions`, `POST /anthropic/v1/messages`, and the short local alias `POST /anthropic/messages`.
- Pricing uses current DeepSeek USD token pricing for `deepseek-v4-flash` and `deepseek-v4-pro`; `deepseek-chat` and `deepseek-reasoner` map to `deepseek-v4-flash`.
- Local app bundle is unsigned and not notarized.
- Future provider types such as Anthropic, Codex, or window quota plans should implement the core provider capability model rather than changing dashboard code directly.
