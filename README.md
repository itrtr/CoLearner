# CoLearner

A native macOS reader that pairs a PDF viewer with an AI study companion. Open a
paper, book, or notes PDF; pick a context (selection, page, section, or whole
document); and ask the assistant to explain, simplify, give examples, quiz you,
or highlight what to remember.

- **Platform:** macOS 14+ (Apple Silicon)
- **Stack:** Swift 6, SwiftUI + AppKit + PDFKit, Swift Package Manager
- **No API keys:** sign in with an existing Claude (Pro/Max) or ChatGPT
  (Plus/Pro/Team) subscription via OAuth — CoLearner calls the APIs directly.

## Build & run

```bash
# Build + launch the app (assembles /tmp/CoLearner.app)
make run

# Or build only
make build

# Run the unit tests (CoLearnerCore)
make test
```

There is also a double-clickable `CoLearner.command` and a `run` script that do
the same `build → launch` flow.

## Architecture

Two SPM targets keep all AI/networking logic UI-free and testable:

| Target | Role |
| --- | --- |
| `CoLearnerCore` (library) | `StudyAgent` protocol + agents, OAuth, direct HTTP/SSE API clients, command running, payload parsing |
| `CoLearnerApp` (executable) | SwiftUI/AppKit shell, `ReaderViewModel`, PDFKit view, markdown rendering, notes |

### Study agents

All conform to a single `StudyAgent` protocol (`respond` + `stream`):

- **`LocalStudyAgent`** — offline deterministic helper (sentence/keyword heuristics). No network.
- **`ExternalStudyAgent`** — shells out to a local CLI (`opencode`, `pi`, `hermes`) and parses the structured JSON response.
- **`DirectAnthropicStudyAgent` / `DirectOpenAIStudyAgent`** — stream directly from the Anthropic Messages API and the OpenAI Codex Responses API using a subscription OAuth token. A `record_metadata` tool call extracts the structured study response (title, key ideas, highlights, …) from the model.

### OAuth (subscription sign-in)

A full PKCE authorization-code flow that mirrors Claude Code and the Codex CLI,
so you sign in with your existing subscription — no API keys, no billing:

- `OAuthSessionManager` (actor) — login, refresh, sign-out, in-flight dedup.
- `AnthropicOAuth` (port 53692) and `OpenAIOAuth` (port 1455) with a loopback
  callback server (`LocalCallbackServer`).
- Credentials are stored as `0600` JSON in
  `~/Library/Application Support/CoLearner/credentials/` by default
  (`FileCredentialStore`), which avoids the Keychain ACL re-prompt loop that
  ad-hoc-signed dev builds hit. Keychain and in-memory stores are also available.

### UI

A 3-pane window: **sidebar** (outline, search, notes, display settings),
**reader** (PDFKit with AI squiggly highlights + user color highlights), and the
**AI companion** panel (provider/model menus, context scope, streaming markdown
chat, notes workspace). Quick actions: Explain, Simplify, Examples, Quiz, Key
points, Highlight.

## Keyboard shortcuts

- `⌘O` — Open PDF
- `⌘F` — Find in document (focuses the sidebar search)
- Assistant menu — Explain / Simplify / Examples / Quiz on the current context

## Project layout

```
Sources/CoLearnerCore/   StudyAgent, agents, OAuth, direct API clients, parsing
Sources/CoLearnerApp/    SwiftUI shell, ReaderViewModel, PDFKit view, markdown
Tests/CoLearnerCoreTests Unit tests for core agents, parsing, command running
scripts/                 build-app.sh, run-dev.sh, test.sh, repair-swiftpm-cache.sh
Package.swift            SPM manifest (macOS 14+, Swift 6)
```

## Notes

- The app remembers the last-opened document and reopens it on launch.
- "Save annotated copy" exports the PDF with your color highlights (AI squiggly
  highlights are display-only by design).
- CLI providers (`opencode`, `pi`, `hermes`) require their respective tools to be
  installed and authenticated; CoLearner reports a setup hint if one is missing.
