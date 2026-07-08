# Ainalytics

**See every AI subscription limit you're paying for — in one menu-bar glance.**

Ainalytics is a native macOS menu-bar app that tracks your usage limits across
**Claude (Code / Max)** and **ChatGPT (Codex)** in one place. It reads the
tokens your own CLIs already store — **read-only, on your Mac, and nowhere
else** — and asks each provider's own usage endpoint how much you have left.
No browser cookies, no Full Disk Access, no account to create, **zero
telemetry**.

Built for vibe developers, by a vibe developer. Free and open source — because
for an app that touches your credentials, the source *is* the trust.

<!-- Screenshots: add docs/menubar.png, docs/dashboard.png before the public release. -->

---

## Why

If you live in Claude Code and Codex all day, you're juggling several limits at
once — the 5-hour session window, the weekly cap, the monthly reset — across two
providers, each behind its own CLI. There was no single place to see "how much
have I got left, and when does it reset?" Ainalytics is that place.

## The trust model — how it works

This is the part that matters, so it's first.

- **Read-only, in memory.** Ainalytics reads the credential files your CLIs
  already wrote — `~/.claude/.credentials.json` (or the Claude Keychain item via
  Apple's own `/usr/bin/security`), `~/.codex/auth.json` — and holds the token
  in memory only. It is **never copied to disk, never logged, never written
  back.** If a token is expired, Ainalytics asks *you* to re-login in your CLI;
  it never refreshes or rewrites your credentials.
- **Your token talks only to the providers.** With that token it calls the same
  private usage endpoint the official CLI calls (`/api/oauth/usage` for Claude,
  `wham/usage` for ChatGPT), impersonating the CLI. Your credentials and usage
  data go to **Anthropic's and OpenAI's own APIs and nowhere else**. The app
  makes two other network calls that carry **none of your data**: an anonymous
  fetch of a public model-price list ([models.dev](https://models.dev)) for the
  cost estimates, and the in-app update check against the Sparkle release feed
  on GitHub. Neither sends your token, your usage, or anything that identifies
  you.
- **No browser, no cookies, no Full Disk Access.** Ainalytics never reads your
  browser, never scrapes cookies, and is **not** in your Full Disk Access list.
  It reads plain home-directory dotfiles and its own Keychain item — nothing in
  another app's protected container.
- **Zero telemetry.** No analytics, no crash reporting, no "anonymous usage
  data." The bundled [`PrivacyInfo.xcprivacy`](Ainalytics/Resources/PrivacyInfo.xcprivacy)
  declares no tracking and no collected data, and the source backs that up.
- **Notarized.** Every release is signed with a Developer ID and notarized by
  Apple. On macOS Tahoe this is also what lets Ainalytics read those dotfiles
  *without* prompting you for Full Disk Access.

The open-source code is the guarantee. Read it, build it yourself, and verify
every word above.

## What it shows

- **Menu bar** — at-a-glance remaining headroom per provider, severity-tinted
  (green → red as a limit nears), with reset/renewal countdowns.
- **Dashboard** — a radial gauge per limit window, a daily-usage chart, and
  per-provider cards.
- **Activity** — a GitHub-style heatmap of your real per-day activity, built
  from your local CLI logs, plus peak-hour and streak insights.
- **Cost** — an API-equivalent estimate ("what would this have cost on the
  API"), your subscription's ROI, and a plan-fit check ("are you on the right
  tier, or could you size down?").
- **Forecast** — a burn-rate projection of when you'll run out this cycle.
- **Notifications** — threshold warnings (e.g. 80% used) and limit-reset alerts.
- **Widget** — a right-click-configurable WidgetKit widget for the same numbers
  on your desktop / Notification Center.

Fully localized: English (US/UK), Turkish, German, Spanish.

## Requirements

- **macOS 26 (Tahoe) or later**, Apple Silicon.
- At least one supported AI CLI **installed and logged in** — Ainalytics reads
  the credentials these tools already store on your Mac. It never asks you to
  log in again.
  - [Claude Code](https://claude.com/claude-code) — Claude / Max
  - [Codex CLI](https://github.com/openai/codex) — ChatGPT / OpenAI

**If neither CLI is installed and logged in, there is nothing for Ainalytics to
read** — every provider will show a "connection lost" state. Each provider also
degrades gracefully on its own: if one endpoint changes or a single CLI is
logged out, that provider shows "connection lost" and the others keep working.

## Install

**Download the `.dmg`** from the [latest release](https://github.com/beyazitcoban/ainalytics/releases/latest),
open it, and drag Ainalytics to Applications. The build is notarized, so it
opens without Gatekeeper warnings. Updates are delivered in-app via Sparkle.

Ainalytics lives in the **menu bar** — after launching, look for its icon at the
top-right of your screen. It has no Dock icon or window.

_A Homebrew cask is planned for a future release._

## Building from source

```sh
brew install xcodegen        # generates the Xcode project from project.yml
xcodegen generate
open Ainalytics.xcodeproj     # build & run with Xcode 26+ (macOS 26 SDK)
```

The project is plain Swift + SwiftUI + SwiftData + WidgetKit — no third-party
runtime dependencies (Sparkle is the only package, used for updates).

## A note on the endpoints

Ainalytics rests on two private, undocumented usage endpoints. Anthropic and
OpenAI can change or remove them at any time without notice — if a provider
breaks, expect a fix in a patch release, and the app keeps working for the
others in the meantime. The data layer is deliberately swappable so a broken
endpoint can be patched in one file.

## Not affiliated

Ainalytics is an independent, unofficial tool. It is not affiliated with,
endorsed by, or sponsored by Anthropic or OpenAI. "Claude", "ChatGPT", and
"Codex" are trademarks of their respective owners.

## License

[MIT](LICENSE) © 2026 Beyazıt Çoban
