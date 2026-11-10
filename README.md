# ✳ Quick Claude

**Your Copilot key, now for Claude.** New Windows laptops ship with a Copilot key you never asked for. Quick Claude turns it into a Claude key: press it, ask anything, and the answer appears right in a liquid-glass popup. Press Esc and it's gone.

> **Windows only.** This is for Windows PCs with a Copilot key. Other keyboards and other operating systems aren't supported.

| | Copilot key does |
| --- | --- |
| **Before** | Opens the Microsoft Copilot app |
| **After** | Opens a Claude popup over whatever you're doing. Copilot never opens |

The Copilot key secretly sends `Win+Shift+F23`. Quick Claude catches just that combination before Windows hands it to Copilot. Uninstall and Copilot gets its key back.

**Website:** https://awnsh.github.io/quick-claude

> Unofficial and independent. Not affiliated with or endorsed by Anthropic. Claude is a trademark of Anthropic.

## Install

Open PowerShell (no admin needed) and run:

```powershell
irm https://raw.githubusercontent.com/awnsh/quick-claude/main/install.ps1 | iex
```

If the installer says Claude Code isn't signed in yet, run this once:

```powershell
claude auth login
```

Then press your Copilot key.

### Requirements

- Windows 11 or 10 with a Copilot key
- A paid Claude plan that includes Claude Code (Pro or higher)
- Claude Code: the copy bundled with the Claude desktop app works, or install it with `irm https://claude.ai/install.ps1 | iex`
- The Claude desktop app, only for Ctrl+Enter

## Keys

| Key | What it does |
| --- | --- |
| **Copilot** | Open or close the popup |
| **Enter** | Ask; the reply streams in under your question. Keep typing to follow up |
| **Ctrl+Enter** | Hand the question to the Claude desktop app's Quick Entry, so it's saved to your chat history |
| **Esc** / click away | Close the popup and clear the conversation |

## How it works

- The Copilot key sends `Win+Shift+F23`. A low-level keyboard hook catches only that combination, blocks it from reaching Copilot, and toggles the popup.
- Questions go to the **Claude Code CLI** in print mode (`claude -p`) with streaming JSON output, tools turned off, and a short "be concise" system prompt. It uses your existing Claude plan, with no API key.
- The glass is a blurred snapshot of the screen behind the popup, taken when it opens, drawn inside an anti-aliased pill with a sheen and specular rim.
- **Ctrl+Enter** puts your question on the clipboard and presses `Ctrl+Alt+Space` (the Claude app's Quick Entry shortcut on Windows). It pastes and submits only after confirming the Claude app has focus, then restores your clipboard text.
- It's one readable PowerShell file with embedded C# (WPF), and there's nothing to compile ahead of time.

## Customize

Edit `%LOCALAPPDATA%\QuickClaude\quick-claude.ps1`:

- `Model`: `sonnet` by default (`haiku` for speed, `opus` for depth)
- `SysPrompt`: how Claude should answer
- `GlassTint`, `Radius`, `CardWidth`: the look

Then restart it by signing out and back in, or by re-running the installer.

## Uninstall

```powershell
irm https://raw.githubusercontent.com/awnsh/quick-claude/main/uninstall.ps1 | iex
```

This stops the popup, removes the Startup launcher, and deletes `%LOCALAPPDATA%\QuickClaude`. Your Copilot key goes back to normal.

## Privacy

- Popup (Enter) chats are **not** added to your Claude chat history. Claude Code keeps a local transcript under `%USERPROFILE%\.claude\projects\`.
- The screen snapshot used for the glass effect stays in memory and is discarded when the popup closes. It is never saved or sent anywhere.
- The keyboard hook only acts on `F23`. Every other key passes straight through untouched.

## License

[MIT](LICENSE)
