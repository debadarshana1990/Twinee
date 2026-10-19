## ⚠️ Please read before you click anything

**Twinee is a personal project, and every line of it was written by AI.** I steer, the AI types, and nobody — including me — has reviewed it the way a grown-up engineer would. I'm a C programmer; this is Swift; we are both guessing.

- It may have bugs, rough edges, or opinions.
- Keep backups of anything you care about (`~/Library/Application Support/Twinee`).
- The AI chat panel runs command-line tools *you* install (Copilot, Gemini, Claude, Codex). Twinee does not ship with any of them, and the page you're reading is sent to whichever one you pick.
- No warranty, no support contract, no pager. MIT licensed.

---

# Twinee 3.0.0 — "Now with 100% more sticky notes"

The last release was a candidate. This one is a *decision*. 🎉

### 📝 Pages grew up
Pages are now wiki-style (hello, Confluence cosplay):
- Big title, colour strip, byline with word count, project/type pickers, link field and **label chips**.
- **Insert menu**: Info / Note / Success / Warning / Error panels, status tags (TO DO, IN PROGRESS, DONE, BLOCKED, IN REVIEW) and dividers.
- **"On this page" outline** that jumps to your headings.
- Readable column or full-window width — your call.
- **Sticky notes** in light red, light blue or light green. Drag, resize, recolour, regret.
- Rename and delete pages from the sidebar (yes, that was broken before; we don't talk about it).

### 🖍️ Whiteboards
One global whiteboard and one per project. Pen, eraser, colours, undo. Picasso not included.

### 🔎 Code Browser, now with fewer excuses
- **Open from Git**: paste a URL, pick a branch, read the code. No clone to manage, no repo list to tidy.
- Opens **any text file**, not just C/C++/Python.
- **HTML Preview** mode (scripts off, because trust issues).
- **Notes on code lines**, saved per repository and shown in the gutter.

### ✨ AI chat panel (⇧⌘I)
A VS Code-style panel on the right that can read whatever page you have open. Pick GitHub Copilot, Gemini, Claude or Codex — whichever CLI you have installed.

### 🪟 Interface
- Resizable sidebars and an AI panel.
- Collapse the sidebar for a full page; hover the left edge to peek.
- Colour. So much colour.
- **Help ▸ Twinee Help** now tells you the version, so you can report bugs against the right one.

---

## Install

1. Download **Twinee-3.0.0.dmg** below, open it, drag Twinee to Applications.
2. The app is **ad-hoc signed, not notarized**, so macOS will frown at it. Control-click → **Open**, or on macOS 15+ use **System Settings → Privacy & Security → Open Anyway**, or run `xattr -dr com.apple.quarantine /Applications/Twinee.app`.
3. Only do that if you trust the source. Reading the warnings above counts as due diligence.

Universal binary (Apple silicon + Intel), macOS 13+.

**Known honest limitations:** AI features need a separately installed CLI; private HTTPS repos can't prompt for credentials; I have not personally audited the code, and neither has the AI.
