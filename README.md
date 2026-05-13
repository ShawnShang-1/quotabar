# QuotaBar

中文 | [English](#english)

QuotaBar 是一个原生 macOS 状态栏 App，用来监控通过本机代理调用 DeepSeek API 的余额、用量、Token 和花费。它把真实 DeepSeek API Key 放进 macOS Keychain，让 Claude Code、CC Switch 或其他 OpenAI/Anthropic-compatible 客户端只接触本机代理 token。

当前版本专注 DeepSeek。未来可以继续扩展 Anthropic、Codex 或其他 coding plan 的 5 小时/周额度窗口。

## 下载

当前包是本机自用风格的 ad-hoc 签名版本，未做 Apple Developer ID 公证。第一次打开时 macOS 可能提示安全警告。

- 下载当前版本：[QuotaBar-v0.1.0-macOS.zip](release-assets/QuotaBar-v0.1.0-macOS.zip)
- 或到 GitHub Releases 下载未来版本：[Releases](https://github.com/ShawnShang-1/quotabar/releases)

安装：

1. 下载并解压 `QuotaBar-v0.1.0-macOS.zip`。
2. 把 `QuotaBar.app` 拖到 `/Applications`。
3. 如果 macOS 阻止打开，右键点击 `QuotaBar.app`，选择“打开”。也可以在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/QuotaBar.app
open /Applications/QuotaBar.app
```

## 它能做什么

- 状态栏常驻显示余额和今日花费。
- Popover 显示 DeepSeek 余额、今日预算进度、按模型今日 Token/花费、本月趋势。
- 支持 `deepseek-v4-flash` 和 `deepseek-v4-pro` 的 CNY 价格估算，可在设置里调整缓存命中、缓存未命中、输出价格。
- 内置本机代理：
  - OpenAI-compatible: `http://127.0.0.1:3847/v1`
  - Anthropic-compatible DeepSeek: `http://127.0.0.1:3847/anthropic`
- 支持 Claude Code + CC Switch，把请求穿过 QuotaBar 后再转给 DeepSeek。
- DeepSeek API Key 存在 macOS Keychain。
- 本地账本只记录元数据，不保存 prompt 或 response 正文。
- 自动启动恢复、余额刷新、异常提醒、代理健康检查。

## 隐私设计

QuotaBar 只保存这些元数据：

- 时间
- provider
- model
- input/output/cache token 数
- 估算花费
- HTTP status code
- 请求耗时
- client label
- 是否异常

它不会保存你的 prompt、response、文件内容或对话正文。真实 DeepSeek API Key 存在 Keychain；外部工具只需要 QuotaBar 的本机 bearer token。

## 配置 Claude Code / CC Switch

先在 QuotaBar 设置里保存真实 DeepSeek API Key，然后在 CC Switch 里这样填：

- API Key：填写 QuotaBar 设置里的本机 bearer token，不要填真实 DeepSeek key
- 请求地址：`http://127.0.0.1:3847/anthropic`
- API 格式：`Anthropic Messages`

Claude Code 配置示例：

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

OpenAI-compatible 客户端配置：

```bash
export OPENAI_BASE_URL="http://127.0.0.1:3847/v1"
export OPENAI_API_KEY="<QuotaBar local bearer token>"
```

## 从源码运行

要求：

- macOS 26
- Swift 6.3 或更新版本

```bash
swift test
swift run QuotaBar
```

直接 `swift run` 时，系统通知可能因为不在 `.app` bundle 内而受限；菜单栏和本机代理仍可用于开发。

## 本地打包

```bash
Scripts/package-local-app.sh
open dist/QuotaBar.app
```

脚本会生成 `dist/QuotaBar.app`，设置 `LSUIElement`，并做 ad-hoc codesign。它适合本机和开源 Release 使用，不等同于上架或公证版本。

## 开发状态

已覆盖的核心测试：

- DeepSeek 余额解析
- OpenAI-compatible 与 Anthropic Messages 代理转发
- streaming SSE usage 记录
- Keychain 保存/读取/删除
- CNY 价格估算
- SwiftData 账本聚合
- 设置持久化
- 代理端口占用、restart、非法 header/body 防护
- 打包脚本和 app bundle 签名校验

当前边界：

- v1/v2 仍只支持 DeepSeek。
- 支持路由：`POST /v1/chat/completions`、`POST /anthropic/v1/messages`、`POST /anthropic/messages`。
- App 未做 Developer ID 签名和 notarization。
- 图表和统计只依赖经过 QuotaBar 本机代理的请求；直接打 DeepSeek 官方 URL 的请求只能体现在余额变化里，不会进入本地用量账本。

## License

MIT License. See [LICENSE](LICENSE).

---

## English

QuotaBar is a native macOS menu bar app for watching DeepSeek API balance, usage, tokens, and estimated CNY spend through a local proxy. It keeps your real DeepSeek API key in macOS Keychain, while Claude Code, CC Switch, and other OpenAI/Anthropic-compatible clients only see a local bearer token.

The current release focuses on DeepSeek. The architecture leaves room for Anthropic, Codex, and coding-plan quota windows later.

## Download

The current build is ad-hoc signed and not notarized with Apple Developer ID. macOS may show a security warning the first time you open it.

- Download current build: [QuotaBar-v0.1.0-macOS.zip](release-assets/QuotaBar-v0.1.0-macOS.zip)
- Future builds: [GitHub Releases](https://github.com/ShawnShang-1/quotabar/releases)

Install:

1. Download and unzip `QuotaBar-v0.1.0-macOS.zip`.
2. Move `QuotaBar.app` to `/Applications`.
3. If macOS blocks it, right-click the app and choose Open. You can also run:

```bash
xattr -dr com.apple.quarantine /Applications/QuotaBar.app
open /Applications/QuotaBar.app
```

## Features

- Always-on menu bar balance and today spend.
- Popover dashboard with DeepSeek balance, daily budget progress, today-by-model tokens/spend, and 30-day trend.
- CNY pricing for `deepseek-v4-flash` and `deepseek-v4-pro`, editable in Settings.
- Built-in local proxy:
  - OpenAI-compatible: `http://127.0.0.1:3847/v1`
  - Anthropic-compatible DeepSeek: `http://127.0.0.1:3847/anthropic`
- Works with Claude Code and CC Switch when routed through QuotaBar.
- Stores the real DeepSeek API key in macOS Keychain.
- Records metadata only, never prompts or responses.
- Startup restore, balance refresh, anomaly alerts, and proxy health checks.

## Privacy

QuotaBar stores only metadata:

- timestamp
- provider
- model
- input/output/cache token counts
- estimated cost
- HTTP status code
- request duration
- client label
- anomaly flag

It does not store prompts, responses, file contents, or conversation text. Your real DeepSeek API key stays in Keychain; external tools use only QuotaBar's local bearer token.

## Claude Code / CC Switch

Save the real DeepSeek API key in QuotaBar first. Then configure CC Switch like this:

- API Key: QuotaBar local bearer token, not the real DeepSeek key
- Request URL: `http://127.0.0.1:3847/anthropic`
- API format: `Anthropic Messages`

Claude Code example:

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

OpenAI-compatible clients:

```bash
export OPENAI_BASE_URL="http://127.0.0.1:3847/v1"
export OPENAI_API_KEY="<QuotaBar local bearer token>"
```

## Run From Source

Requirements:

- macOS 26
- Swift 6.3 or newer

```bash
swift test
swift run QuotaBar
```

When launched with `swift run`, system notifications may be limited because the process is not inside an app bundle. The menu bar app and proxy still work for development.

## Package Locally

```bash
Scripts/package-local-app.sh
open dist/QuotaBar.app
```

The script creates `dist/QuotaBar.app`, enables `LSUIElement`, and applies ad-hoc codesigning. It is suitable for local use and open-source release assets, not for App Store-style distribution.

## Development Status

Core test coverage includes:

- DeepSeek balance parsing
- OpenAI-compatible and Anthropic Messages proxy forwarding
- streaming SSE usage recording
- Keychain save/load/delete
- CNY pricing estimates
- SwiftData ledger aggregation
- persistent settings
- proxy port conflicts, restart, malformed header/body protection
- packaging and app bundle signing checks

Current boundaries:

- DeepSeek only.
- Supported routes: `POST /v1/chat/completions`, `POST /anthropic/v1/messages`, `POST /anthropic/messages`.
- No Developer ID signing or notarization yet.
- Charts and usage stats only include requests that go through the QuotaBar local proxy. Direct calls to DeepSeek will change balance but will not enter the local usage ledger.

## License

MIT License. See [LICENSE](LICENSE).
