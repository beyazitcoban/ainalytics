# Ainalytics

**One menu-bar glance at every AI subscription limit you're paying for.**

A native macOS menu-bar app that tracks your usage limits for **Claude (Code /
Max)** and **ChatGPT (Codex)** in one place — session, weekly and monthly
windows, with reset countdowns, a dashboard, and notifications. Free and open
source.

## How it works

Ainalytics reads the credential tokens your own CLIs already store —
**read-only, on your Mac, and nowhere else** — and asks each provider's own
usage endpoint how much you have left.

- **Read-only, in memory.** It reads `~/.claude/.credentials.json` (or the
  Claude Keychain item) and `~/.codex/auth.json`, keeps the token in memory
  only, and never writes, logs, or copies it.
- **Your token talks only to the providers.** Usage requests go to Anthropic's
  and OpenAI's own APIs — nowhere else.
- **No browser, no cookies, no Full Disk Access, zero telemetry.** Every
  release is Developer-ID signed and notarized by Apple.

The open-source code is the guarantee — read it, build it, verify it.

## Download

[**Download the latest `.dmg`**](https://github.com/beyazitcoban/ainalytics/releases/latest),
open it, and drag Ainalytics to Applications. It's notarized (no Gatekeeper
warnings); updates arrive in-app via Sparkle. Ainalytics lives in the **menu
bar** (top-right) — no Dock icon or window.

**Requirements:** macOS 26 (Tahoe)+ on Apple Silicon, and at least one supported
CLI installed and logged in — [Claude Code](https://claude.com/claude-code) or
the [Codex CLI](https://github.com/openai/codex).

---

Independent, unofficial tool — not affiliated with Anthropic or OpenAI.
[MIT](LICENSE) © 2026 Beyazıt Çoban
