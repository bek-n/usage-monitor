# Usage Monitor

A macOS menu bar app that shows the plan usage limits (5-hour session and weekly) of several Claude accounts at once, so you don't have to sign out and back in to check each one.

## How it works

- Each account lives in its own Claude Code profile folder, `~/.claude-accounts/<name>`. You sign in to each one once with `claude auth login`. Your normal Claude Code login (`~/.claude`) isn't touched.
- To read the limits, the app starts Claude Code for each profile and sends it the read-only `get_usage` control request, the same data the `/usage` command shows. It sends no prompt and uses no tokens. The app never reads, stores, or sends any login token itself; Claude Code handles authentication.
- The menu bar shows each account's session usage, for example `71% · 12%`. Click the icon for the full panel; right-click for a quick summary.
- The account Claude Code is currently signed in with gets an **In Claude Code** tag.

## Requirements

- macOS 12 or later.
- Claude Code, either the CLI or the VS Code / Cursor extension. The app finds the binary automatically; you can also set its path in Settings.

## Use another account in the terminal without signing out

Each card's ⋯ menu has **Copy terminal command**, for example:

```sh
CLAUDE_CONFIG_DIR=~/.claude-accounts/work claude
```

In VS Code, the `claudeCode.environmentVariables` setting accepts `CLAUDE_CONFIG_DIR` as an absolute path. Note that a profile folder has its own settings, history and memory.

## Build

```sh
flutter build macos --release
cp -R "build/macos/Build/Products/Release/Usage Monitor.app" /Applications/
```

## Caveats

- `get_usage` is marked experimental in the Claude Agent SDK, so a future Claude Code release may change it.
- If you sign in to a profile in a browser that's already signed in to another Claude account, sign out there first or use a private window.
